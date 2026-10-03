import CDar
import Foundation

/// DAR is a sliced backup format. Each operation opens libdar on a blocking
/// worker; the engine keeps only cancellation handles, never archive contents.
final actor ArchiveDarEngine: ArchiveEngine {
    private var continuation: AsyncStream<EngineStatus>.Continuation?
    private var operations: [UUID: DarOperation] = [:]

    func statusStream() -> AsyncStream<EngineStatus> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(.idle)
        }
    }

    func cancel() async { for operation in operations.values { operation.cancel() } }

    func loadArchive(url: URL, passwordResolver: @escaping ArchivePasswordResolver) async throws -> ArchiveEngineLoadResult {
        let (operation, key) = try begin()
        defer { operations[key] = nil }
        let entries = try await read(url, operation: operation, resolver: passwordResolver).entries
        var items: [UUID: ArchiveItem] = [:]
        var size: Int64 = 0
        for (index, entry) in entries.enumerated() {
            let item = ArchiveItem(index: UInt32(index), name: (entry.path as NSString).lastPathComponent,
                                   virtualPath: entry.path, type: entry.kind == 1 ? .directory : .file,
                                   compressedSize: Int(clamping: entry.packed), uncompressedSize: Int(clamping: entry.size),
                                   modificationDate: Date(timeIntervalSince1970: TimeInterval(entry.mtime)))
            items[item.id] = item
            let (sum, overflow) = size.addingReportingOverflow(Int64(clamping: entry.size))
            size = overflow ? Int64.max : sum
        }
        continuation?.yield(.done)
        return ArchiveEngineLoadResult(items: items, hasTree: false, uncompressedSize: size,
                                       isEncrypted: mp_dar_encrypted(operation.handle) != 0)
    }

    func extract(items: [ArchiveItem], from url: URL, to destination: URL,
                 passwordResolver: @escaping ArchivePasswordResolver) async throws -> ArchiveExtractionResult {
        guard !items.isEmpty else { throw ArchiveError.extractionFailed("No items to extract") }
        let paths = try items.map { item -> String in
            guard let path = item.virtualPath, !path.isEmpty else { throw ArchiveError.extractionFailed("Missing DAR entry path") }
            return path
        }
        try await extract(url, to: destination, selection: paths, resolver: passwordResolver)
        return ArchiveExtractionResult(urlsByItemID: Dictionary(uniqueKeysWithValues: zip(items, paths).map {
            ($0.0.id, destination.appendingPathComponent($0.1))
        }))
    }

    func extract(_ url: URL, to destination: URL, passwordResolver: @escaping ArchivePasswordResolver) async throws {
        try await extract(url, to: destination, selection: [], resolver: passwordResolver)
    }

    private func begin() throws -> (DarOperation, UUID) {
        let operation = try DarOperation()
        let key = UUID()
        operations[key] = operation
        return (operation, key)
    }

    /// A password retry reopens the archive; no password is persisted by this engine.
    private func read(_ url: URL, operation: DarOperation, resolver: @escaping ArchivePasswordResolver) async throws
        -> (source: DarVolume, entries: [DarEntry], password: String?) {
        let attempts = ArchivePasswordAttempts(url: url, resolver: resolver)
        var password: String?
        while true {
            do {
                let supplied = password
                return try await withTaskCancellationHandler {
                    try Task.checkCancellation()
                    return try await runBlocking {
                        try Sandbox.accessSync(url: url) {
                            let source = try DarVolume(url: url)
                            let entries = try operation.read(source, password: supplied)
                            return (source, entries, supplied)
                        }
                    }
                } onCancel: { operation.cancel() }
            } catch DarFailure.password {
                password = try await attempts.next()
            }
        }
    }

    /// Restore into a fresh private directory first. Failed or cancelled restores
    /// never install partial files; existing destination items are not overwritten.
    private func extract(_ url: URL, to destination: URL, selection: [String], resolver: @escaping ArchivePasswordResolver) async throws {
        let (operation, key) = try begin()
        defer { operations[key] = nil }
        let opened = try await read(url, operation: operation, resolver: resolver)
        try DarEntry.validate(opened.entries, selection: selection)
        let stage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stage) }
        try await withTaskCancellationHandler {
            try await runBlocking {
                try Sandbox.accessSync(url: url) {
                    try operation.extract(opened.source, password: opened.password, to: stage, selection: selection)
                }
            }
            try Task.checkCancellation()
            try Sandbox.accessSync(url: destination) {
                try DarEntry.install(from: stage, to: destination)
            }
        } onCancel: { operation.cancel() }
        continuation?.yield(.done)
    }
}

private enum DarFailure: Error { case password }

/// The C handle serializes cancellation with the worker's libdar thread ID.
private final class DarOperation: @unchecked Sendable {
    let handle: OpaquePointer
    init() throws {
        guard let handle = mp_dar_create() else { throw ArchiveError.loadFailed("Could not allocate DAR operation") }
        self.handle = handle
    }
    deinit { mp_dar_free(handle) }
    func cancel() { mp_dar_cancel(handle) }
    private func check(_ result: Int32) throws {
        switch result {
        case 0: return
        case 2: throw DarFailure.password
        case 3: throw CancellationError()
        default: throw ArchiveError.extractionFailed(String(cString: mp_dar_error(handle)))
        }
    }
    func read(_ source: DarVolume, password: String?) throws -> [DarEntry] {
        try check(mp_dar_read(handle, source.folder.path, source.base, source.fileExtension, source.digits, password))
        return (0..<mp_dar_count(handle)).map { index in
            DarEntry(path: String(cString: mp_dar_path(handle, index)),
                     link: String(cString: mp_dar_link(handle, index)),
                     size: mp_dar_size(handle, index), packed: mp_dar_packed_size(handle, index),
                     mtime: mp_dar_mtime(handle, index), kind: mp_dar_kind(handle, index),
                     available: mp_dar_available(handle, index) != 0)
        }
    }
    func extract(_ source: DarVolume, password: String?, to destination: URL, selection: [String]) throws {
        let strings = selection.map { strdup($0) }
        defer { strings.forEach { free($0) } }
        let pointers = strings.map { $0.map { UnsafePointer($0) } }
        try pointers.withUnsafeBufferPointer {
            try check(mp_dar_extract(handle, source.folder.path, source.base, source.fileExtension, source.digits, password,
                                     destination.path, $0.baseAddress, $0.count))
        }
    }
}

/// DAR always uses numbered slices, including archives that fit in one file.
struct DarVolume: Sendable {
    let folder: URL
    let base: String
    let digits: UInt32
    let firstURL: URL
    let fileExtension: String
    init(url: URL) throws {
        let stem = url.deletingPathExtension().lastPathComponent
        guard url.pathExtension.lowercased() == "dar", let dot = stem.lastIndex(of: "."),
              !stem[stem.index(after: dot)...].isEmpty,
              stem[stem.index(after: dot)...].allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw ArchiveError.invalidArchive("DAR archives need their original numbered names, such as backup.1.dar.")
        }
        base = String(stem[..<dot])
        folder = url.deletingLastPathComponent()
        let pattern = "^" + NSRegularExpression.escapedPattern(for: base) + #"\.(0*)1\.dar$"#
        let siblings = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        let first = siblings.filter {
            $0.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        guard first.count == 1, let name = first.first else {
            throw ArchiveError.invalidArchive("DAR needs exactly one first slice for \(base). Keep all slices together with their original names.")
        }
        firstURL = folder.appendingPathComponent(name)
        fileExtension = firstURL.pathExtension
        let number = name.dropFirst(base.count + 1).dropLast(4)
        digits = number.hasPrefix("0") ? UInt32(number.count) : 0
        let slicePattern = "^" + NSRegularExpression.escapedPattern(for: base) + #"\.[0-9]+\.dar$"#
        let numbers = siblings.filter { $0.range(of: slicePattern, options: [.regularExpression, .caseInsensitive]) != nil }
            .compactMap { Int($0.dropFirst(base.count + 1).dropLast(4)) }.sorted()
        guard numbers.enumerated().allSatisfy({ $0.element == $0.offset + 1 }) else {
            throw ArchiveError.invalidArchive("A DAR slice is missing or duplicated. Keep the complete set together.")
        }
    }
}

struct DarEntry: Sendable {
    let path, link: String
    let size, packed: UInt64
    let mtime: Int64
    let kind: Int32
    let available: Bool

    /// No backup deletion records, devices, unavailable reference data or escaping
    /// paths may be restored through an ordinary archive extraction operation.
    static func validate(_ entries: [DarEntry], selection: [String]) throws {
        var names: Set<String> = []
        for entry in entries {
            guard safe(entry.path), names.insert(entry.path.precomposedStringWithCanonicalMapping.lowercased()).inserted else {
                throw ArchiveError.extractionFailed("Unsafe or conflicting DAR path: " + entry.path)
            }
            let selected = selection.isEmpty || selection.contains { entry.path == $0 || entry.path.hasPrefix($0 + "/") }
            if selected && (!entry.available || entry.kind == 3) {
                throw ArchiveError.extractionFailed("This DAR entry needs backup restoration or an unsupported file type: " + entry.path)
            }
            if entry.kind == 2 {
                guard safe(entry.link), !entries.contains(where: { $0.path.precomposedStringWithCanonicalMapping.lowercased().hasPrefix(entry.path.precomposedStringWithCanonicalMapping.lowercased() + "/") }) else {
                    throw ArchiveError.extractionFailed("Unsafe DAR symbolic link: " + entry.path)
                }
            }
        }
        guard selection.allSatisfy({ path in entries.contains { $0.path == path } }) else {
            throw ArchiveError.extractionFailed("A selected DAR entry is no longer present")
        }
    }
    static func safe(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\0")
            && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    static func install(from stage: URL, to destination: URL) throws {
        let fm = FileManager.default
        let roots = try fm.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil)
        for root in roots {
            let target = destination.appendingPathComponent(root.lastPathComponent)
            if (try? fm.attributesOfItem(atPath: target.path)) != nil {
                throw ArchiveError.extractionFailed("Already exists: " + root.lastPathComponent + ". Choose an empty destination folder.")
            }
        }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        var installed: [URL] = []
        do {
            for root in roots {
                let target = destination.appendingPathComponent(root.lastPathComponent)
                try fm.copyItem(at: root, to: target)
                installed.append(target)
            }
        } catch {
            for target in installed { try? fm.removeItem(at: target) }
            throw error
        }
    }
}
