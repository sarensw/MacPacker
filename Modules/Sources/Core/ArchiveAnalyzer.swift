//
//  ArchiveAnalyzer.swift
//  Modules
//
//  Created by Claude on 16.11.26.
//

import Foundation
import Swift7zip
import UniformTypeIdentifiers
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "analysis")

/// What MacPacker finds out about one archive file, for a bug report about an
/// archive the user cannot share: the file, how it is detected, what 7-Zip says
/// about it and how each engine for its format lists it (#413).
///
/// It names the archive but none of the files in it: of those there are only
/// counts, sizes and methods.
public struct ArchiveAnalysis: Sendable, Equatable {
    public struct Row: Sendable, Equatable {
        public let label: String
        public let value: String
    }

    public struct Section: Sendable, Equatable {
        public let title: String
        public let rows: [Row]

        public func value(_ label: String) -> String? {
            rows.first { $0.label == label }?.value
        }
    }

    /// What the analyzer reports as it goes.
    public enum Progress: Sendable {
        /// The step about to run. An analysis that gets no further stuck there.
        case step(String)
        case section(Section)
    }

    public private(set) var sections: [Section] = []
    /// The step that was running when the report was taken, if one was.
    public private(set) var unfinishedStep: String?

    public init() {}

    public mutating func apply(_ progress: Progress) {
        switch progress {
        case .step(let step): unfinishedStep = step
        case .section(let section): sections.append(section); unfinishedStep = nil
        }
    }

    /// Called once the analysis has ended, however far it got.
    public mutating func finish() {
        unfinishedStep = nil
    }

    public func section(_ title: String) -> Section? {
        sections.first { $0.title == title }
    }

    /// The report as plain text, to paste into a bug report.
    public var text: String {
        var text = "MacPacker archive analysis\n"
        for section in sections {
            text += "\n\(section.title)\n"
            let width = section.rows.map(\.label.count).max() ?? 0
            for row in section.rows {
                text += "  " + row.label.padding(toLength: width, withPad: " ", startingAt: 0) + "  \(row.value)\n"
            }
        }
        if let unfinishedStep {
            text += "\nStill running: \(unfinishedStep)\n"
        }
        return text
    }
}

/// Examines an archive file without opening it in a window. Off the main
/// actor, like the loader, the extractor and the scanner.
public final actor ArchiveAnalyzer {
    private let catalog: ArchiveTypeCatalog
    private let engineSelector: ArchiveEngineSelectorProtocol

    public init(catalog: ArchiveTypeCatalog, engineSelector: ArchiveEngineSelectorProtocol) {
        self.catalog = catalog
        self.engineSelector = engineSelector
    }

    /// The analysis of `url`, step by step. Every step reports a section, so an
    /// archive that hangs an engine still shows everything up to it.
    public nonisolated func analyze(_ url: URL) -> AsyncStream<ArchiveAnalysis.Progress> {
        AsyncStream { continuation in
            let task = Task {
                await self.run(url) { continuation.yield($0) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The whole analysis once it is done.
    public nonisolated func report(for url: URL) async -> ArchiveAnalysis {
        var analysis = ArchiveAnalysis()
        for await progress in analyze(url) { analysis.apply(progress) }
        analysis.finish()
        return analysis
    }

    private func run(_ url: URL, report: @Sendable (ArchiveAnalysis.Progress) -> Void) async {
        let start = Date()
        log.notice("Archive analysis started", context: ["file": url.lastPathComponent])
        func step(_ title: String, _ rows: () async -> [ArchiveAnalysis.Row]) async {
            guard !Task.isCancelled else { return }
            report(.step(title))
            log.notice("Archive analysis step", context: ["file": url.lastPathComponent, "step": title])
            report(.section(ArchiveAnalysis.Section(title: title, rows: await rows())))
        }

        await step("MacPacker") { environmentRows() }
        await step("File") { await Self.blocking { Self.fileRows(url) } }

        let detector = ArchiveTypeDetector(catalog: catalog)
        // A copy, so the closure below holds no `self` and may leave the actor.
        let engineSelector = engineSelector
        var detected: DetectionResult?
        await step("Detection") {
            let (rows, result) = await Self.blocking {
                let result = detector.detect(for: url)
                return (Self.detectionRows(url, detector: detector, detected: result, engineSelector: engineSelector), result)
            }
            detected = result
            return rows
        }

        var properties: [ArchiveAnalysis.Row] = []
        await step("7-Zip") {
            let (rows, archiveProperties) = await Self.blocking { Self.sevenZipRows(url) }
            properties = archiveProperties
            return rows
        }
        if !properties.isEmpty {
            report(.section(ArchiveAnalysis.Section(title: "7-Zip archive properties", rows: properties)))
        }

        // a compound is read as the compressed file around the archive first
        let format = detected.flatMap { result in
            result.composition?.components.last.flatMap { catalog.getType(for: $0) } ?? result.type
        }
        for engine in format?.engines.compactMap({ ArchiveEngineType(configId: $0.id) }) ?? [] {
            await step("Engine: \(engine.rawValue)") { await engineRows(url, engine: engine) }
        }

        log.notice("Archive analysis finished", context: [
            "file": url.lastPathComponent,
            "seconds": Self.seconds(since: start)
        ])
    }

    // MARK: - Steps

    private func environmentRows() -> [ArchiveAnalysis.Row] {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        return [
            .init(label: "Version", value: version),
            .init(label: "macOS", value: ProcessInfo.processInfo.operatingSystemVersionString),
            .init(label: "Architecture", value: architecture),
            .init(label: "Processors", value: "\(ProcessInfo.processInfo.activeProcessorCount)"),
            .init(label: "Engines", value: engineSelector.allowsEngineFallback ? "automatic" : "chosen in Settings"),
            .init(label: "7-Zip", value: ArchiveEngineType.`7zip`.libraryVersion),
            .init(label: "XAD", value: ArchiveEngineType.xad.libraryVersion),
            .init(label: "Date", value: ISO8601DateFormatter().string(from: Date())),
        ]
    }

    private static func fileRows(_ url: URL) -> [ArchiveAnalysis.Row] {
        var rows: [ArchiveAnalysis.Row] = [
            .init(label: "Name", value: url.lastPathComponent),
            .init(label: "Extension", value: url.pathExtension.isEmpty ? "none" : url.pathExtension),
            .init(label: "Location", value: location(of: url)),
        ]
        let keys: Set<URLResourceKey> = [
            .fileSizeKey, .creationDateKey, .contentModificationDateKey, .contentTypeKey,
            .isSymbolicLinkKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
            .volumeIsLocalKey, .volumeIsInternalKey, .volumeIsRemovableKey, .volumeLocalizedFormatDescriptionKey,
        ]
        var fresh = url
        fresh.removeAllCachedResourceValues()
        guard let values = Sandbox.accessSync(url: url, perform: { try? fresh.resourceValues(forKeys: keys) }) else {
            rows.append(.init(label: "Readable", value: "no: its attributes could not be read"))
            return rows
        }
        if let size = values.fileSize {
            rows.append(.init(label: "Size", value: bytes(Int64(size))))
        }
        let dates = ISO8601DateFormatter()
        rows.append(.init(label: "Created", value: values.creationDate.map(dates.string(from:)) ?? "unknown"))
        rows.append(.init(label: "Modified", value: values.contentModificationDate.map(dates.string(from:)) ?? "unknown"))
        rows.append(.init(label: "Content type", value: values.contentType?.identifier ?? "unknown"))
        if values.isSymbolicLink == true {
            rows.append(.init(label: "Symbolic link", value: "yes"))
        }
        if values.isUbiquitousItem == true {
            rows.append(.init(label: "iCloud", value: values.ubiquitousItemDownloadingStatus?.rawValue ?? "yes"))
        }
        let volume = [
            values.volumeLocalizedFormatDescription,
            values.volumeIsLocal == false ? "network" : nil,
            values.volumeIsInternal == true ? "internal" : nil,
            values.volumeIsRemovable == true ? "removable" : nil,
        ].compactMap { $0 }
        rows.append(.init(label: "Volume", value: volume.isEmpty ? "unknown" : volume.joined(separator: ", ")))
        let attributes = Sandbox.accessSync(url: url) { extendedAttributeNames(url) }
        rows.append(.init(label: "Extended attributes", value: attributes.isEmpty ? "none" : attributes.joined(separator: ", ")))
        return rows
    }

    private static func detectionRows(
        _ url: URL, detector: ArchiveTypeDetector, detected: DetectionResult?, engineSelector: ArchiveEngineSelectorProtocol
    ) -> [ArchiveAnalysis.Row] {
        func describe(_ result: DetectionResult?) -> String {
            guard let result else { return "none" }
            var parts = [result.type.id]
            if let composition = result.composition { parts.append("compound \(composition.id)") }
            if let split = result.split { parts.append("split \(split.id) (\(split.scheme))") }
            return parts.joined(separator: ", ")
        }
        let signatures = detector.signatures(in: url)
        var rows: [ArchiveAnalysis.Row] = [
            .init(label: "By extension", value: describe(detector.detectByExtension(for: url, considerComposition: true))),
            .init(label: "By content", value: signatures.isEmpty ? "none" : signatures.joined(separator: "; ")),
        ]
        // Raw bytes only for a file no signature fits, and only 8: enough to
        // tell what it is (an HTML page saved as .zip). Past them a tar header
        // holds a name, and a gzip header the original file name.
        if signatures.isEmpty {
            rows.append(.init(label: "First 8 bytes", value: firstBytes(of: url, count: 8)))
        }
        rows.append(.init(label: "Opens as", value: detected.map { "\(describe($0)) (from \($0.source.rawValue))" } ?? "not an archive MacPacker reads"))
        if let type = detected?.type {
            let engines = type.engines.map { $0.default == true ? "\($0.id) (default)" : $0.id }
            rows.append(.init(label: "Engines", value: engines.joined(separator: ", ")))
            rows.append(.init(label: "Selected", value: engineSelector.engineType(for: type.id)?.configId ?? "none"))
        }
        return rows
    }

    /// What 7-Zip reads from the archive itself, and the properties it reports
    /// for the archive as a whole.
    private static func sevenZipRows(_ url: URL) -> ([ArchiveAnalysis.Row], [ArchiveAnalysis.Row]) {
        let start = Date()
        let archive: SevenZipArchive
        do {
            archive = try Sandbox.accessSync(url: url) { try SevenZipArchive(url: url) }
        } catch SevenZipError.passwordMissing {
            return ([.init(label: "Opened", value: "no: the names are encrypted, a password is needed to list them")], [])
        } catch {
            return ([.init(label: "Opened", value: "no: \(error)")], [])
        }
        let opened = seconds(since: start)
        let levels = Set(archive.archiveProperties.map(\.level)).count
        let properties = archive.archiveProperties.map { property in
            ArchiveAnalysis.Row(label: levels > 1 ? "\(property.level): \(property.name)" : property.name, value: property.value)
        }
        guard let entries = try? archive.entries else {
            return ([.init(label: "Opened as", value: archive.formatName ?? "unknown"),
                     .init(label: "Entries", value: "could not be read")], properties)
        }
        let encoding = Archive7ZipEngine.readNames(of: archive, chosen: nil)
        let files = entries.filter { !$0.isDirectory }
        var methods: [String: Int] = [:]
        for entry in files {
            methods[archive.method(ofEntryAt: entry.index) ?? "unknown", default: 0] += 1
        }
        let dates = entries.compactMap(\.modificationDate)
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        let rows: [ArchiveAnalysis.Row] = [
            .init(label: "Opened as", value: archive.formatName ?? "unknown"),
            .init(label: "Seconds to open", value: opened),
            .init(label: "Items", value: "\(archive.storedItemCount) stored, \(entries.count) listed"),
            .init(label: "Files", value: "\(files.count)"),
            .init(label: "Folders", value: "\(entries.count - files.count)"),
            .init(label: "Encrypted", value: "\(entries.filter(\.isEncrypted).count)"),
            .init(label: "Methods", value: methods.isEmpty ? "none"
                  : methods.sorted { $0.value > $1.value }.map { "\($0.key) ×\($0.value)" }.joined(separator: ", ")),
            .init(label: "Size", value: bytes(Int64(clamping: files.reduce(0) { $0 + $1.size }))),
            .init(label: "Packed", value: bytes(Int64(clamping: files.reduce(0) { $0 + $1.packedSize }))),
            .init(label: "Largest file", value: bytes(Int64(clamping: files.map(\.size).max() ?? 0))),
            .init(label: "Deepest path", value: "\(entries.map { $0.path.split(separator: "/").count }.max() ?? 0) levels"),
            .init(label: "Longest path", value: "\(entries.map(\.path.utf8.count).max() ?? 0) bytes"),
            .init(label: "Non-ASCII names", value: "\(entries.filter { $0.path.unicodeScalars.contains { !$0.isASCII } }.count)"),
            .init(label: "Name encoding", value: encoding?.rawValue ?? "declared by the archive, or ASCII"),
            .init(label: "Tree", value: archive.isTree ? "yes" : "no"),
            .init(label: "Modified", value: dates.isEmpty ? "unknown"
                  : "\(day.string(from: dates.min()!)) to \(day.string(from: dates.max()!))"),
        ]
        return (rows, properties)
    }

    /// Lists the archive the way opening it does, with this engine, and never
    /// asks for a password.
    private func engineRows(_ url: URL, engine type: ArchiveEngineType) async -> [ArchiveAnalysis.Row] {
        let engine = engineSelector.engine(for: type)
        let start = Date()
        do {
            let result = try await Sandbox.access(url: url) {
                try await engine.loadArchive(url: url, passwordResolver: { _ in nil })
            }
            return [
                .init(label: "Entries", value: "\(result.items.count)"),
                .init(label: "Seconds", value: Self.seconds(since: start)),
                .init(label: "Encrypted", value: result.isEncrypted ? "yes" : "no"),
                .init(label: "Tree", value: result.hasTree ? "yes" : "no"),
                .init(label: "Size", value: Self.bytes(result.uncompressedSize)),
                .init(label: "Name encoding", value: result.nameEncoding?.rawValue ?? "declared by the archive, or ASCII"),
            ]
        } catch {
            return [
                .init(label: "Error", value: "\(error)"),
                .init(label: "Seconds", value: Self.seconds(since: start)),
            ]
        }
    }

    // MARK: - Helpers

    /// Off the cooperative pool: reading a file can block for as long as the
    /// volume takes, and 7-Zip's open reads it.
    private static func blocking<T>(_ body: @escaping () -> T) async -> T {
        // ponytail: runBlocking only throws what `body` throws, and this one doesn't
        try! await runBlocking(body)
    }

    /// Where the file is, without the names of the user's own folders: the
    /// folder in the home folder it is under, iCloud Drive, a cloud provider or
    /// another volume.
    static func location(of url: URL) -> String {
        let folder = url.deletingLastPathComponent().standardizedFileURL.path
        guard let pw = getpwuid(getuid()) else { return "unknown" }
        let home = String(cString: pw.pointee.pw_dir)
        if folder == home { return "~" }
        if folder.hasPrefix(home + "/") {
            let parts = folder.dropFirst(home.count + 1).split(separator: "/").map(String.init)
            if parts.starts(with: ["Library", "Mobile Documents"]) { return "iCloud Drive" }
            if parts.starts(with: ["Library", "CloudStorage"]), parts.count > 2 { return "~/Library/CloudStorage/\(parts[2])" }
            return "~/" + parts[0] + (parts.count > 1 ? "/…" : "")
        }
        if folder.hasPrefix("/Volumes/") { return "/Volumes/…" }
        let first = folder.split(separator: "/").first.map(String.init) ?? ""
        return "/" + first + (folder.split(separator: "/").count > 1 ? "/…" : "")
    }

    private static func extendedAttributeNames(_ url: URL) -> [String] {
        let length = listxattr(url.path, nil, 0, XATTR_NOFOLLOW)
        guard length > 0 else { return [] }
        var buffer = [CChar](repeating: 0, count: length)
        guard listxattr(url.path, &buffer, length, XATTR_NOFOLLOW) == length else { return [] }
        return buffer.split(separator: 0).map { String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self) }
    }

    private static func firstBytes(of url: URL, count: Int) -> String {
        Sandbox.accessSync(url: url) {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return "the file could not be read" }
            defer { try? handle.close() }
            return hex((try? handle.read(upToCount: count)) ?? Data())
        }
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    static func bytes(_ count: Int64) -> String {
        "\(count) bytes (\(ByteCountFormatter.string(fromByteCount: count, countStyle: .file)))"
    }

    private static func seconds(since start: Date) -> String {
        String(format: "%.3f", Date().timeIntervalSince(start))
    }
}
