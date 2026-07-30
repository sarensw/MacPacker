//
//  ArchiveXadEngine.swift
//  Modules
//
//  Created by Stephan Arenswald on 25.11.25.
//

import Foundation
import XADMaster

private final class XADArchiveWithPasswordSupport {
    private let url: URL
    private let archive: XADArchive
    private let passwordResolver: ArchivePasswordResolver
    
    init(
        url: URL,
        passwordResolver: @escaping ArchivePasswordResolver
    ) throws {
        // initWithFile:error: over initWithFile: so a failure carries a code
        // instead of a bare nil.
        var openError: XADError = 0
        guard let archive = XADArchive(file: url.path, error: &openError) else {
            // A header-encrypted archive (7z -mhe=on, RAR -hp) can't be opened
            // here at all: the header has to be decrypted during init and
            // XADArchive only accepts a password afterwards. XAD's own hook is
            // the synchronous `archiveNeedsPassword:` delegate, which can't
            // drive our async resolver.
            //
            // XAD reports that as a plain decrunch error, the same code a
            // genuinely damaged archive gets, so we can't state the cause —
            // only name it as the likely one. Either way 7-Zip is the engine
            // that can read it, or say properly that it can't.
            if openError == XADDecrunchError || openError == XADPasswordError {
                throw ArchiveError.invalidArchive(
                    "Could not open \(url.lastPathComponent) with the XAD engine. If the archive has an encrypted header, switch to 7-Zip in Settings.")
            }
            throw ArchiveError.invalidArchive(
                "Could not open \(url.lastPathComponent) (XAD error \(openError))")
        }
        self.url = url
        self.archive = archive
        self.passwordResolver = passwordResolver
    }

    /// Whether any entry is encrypted. Read straight off `archive` rather than
    /// through `performXADOperationWithPasswordRetry`, which would recurse, and
    /// cached because the answer cannot change for an open archive.
    private var hasEncryptedEntry: Bool {
        if let cachedHasEncryptedEntry { return cachedHasEncryptedEntry }
        let count = archive.numberOfEntries()
        let found = (0..<count).contains { archive.entryIsEncrypted($0) }
        cachedHasEncryptedEntry = found
        return found
    }
    private var cachedHasEncryptedEntry: Bool?
    
    /// How many passwords a single operation will ask for before giving up.
    /// A resolver that keeps answering with the same wrong password (a stale
    /// cache, a scripted caller) would otherwise spin this loop forever at full
    /// CPU without ever surfacing an error.
    private static let maxPasswordAttempts = 20

    /// Failures that mean "the bytes did not decode" — on an encrypted archive
    /// that is a wrong or missing password far more often than a damaged file.
    /// Deliberately excludes the unambiguous ones (write, open, out of memory,
    /// skip, break) so a real I/O problem still surfaces as itself.
    private static let passwordSuspectErrors: Set<XADError> = [
        XADUnknownError,      // RAR3/4, wrong password
        XADInputError,        // RAR3/4, wrong password mid-stream
        XADIllegalDataError,
        XADNotSupportedError, // RAR, no password set
        XADDecrunchError,     // 7z
        XADChecksumError
    ]

    func performXADOperationWithPasswordRetry<T>(
        operation: @escaping () -> T
    ) async throws -> T {
        var attempt = 0

        while true {
            archive.clearLastError()

            // blocking XADMaster call — keep it off the cooperative pool
            let value = try await runBlocking { operation() }
            let error = archive.lastError()

            // success
            if error == 0 {
                return value
            }

            // XADMaster only reports XADPasswordError for the formats whose
            // decryptors check the password explicitly — zip, and RAR5 once it
            // gets that far. Everywhere else a missing or wrong password
            // surfaces as whatever the decoder happened to choke on: a decrunch
            // error on 7z, "not fully supported" or an input/unknown error on
            // RAR3/4. The prompt below never ran for those, so the archives
            // failed outright even though XAD reads them fine once the password
            // is set.
            //
            // So on an archive that *has* encrypted entries, treat any
            // data-shaped failure as a possible password problem. Real I/O and
            // resource errors are left alone, and the attempt ceiling stops a
            // genuinely broken archive from looping. Same trade the 7-Zip engine
            // makes for 7z AES, which has no password verifier either.
            let isPasswordError = error == XADPasswordError
                || (hasEncryptedEntry && Self.passwordSuspectErrors.contains(error))

            // failed, but because password is wrong / needed > ask user
            if isPasswordError {
                attempt += 1

                guard attempt <= Self.maxPasswordAttempts else {
                    throw ArchiveError.extractionFailed(
                        "Could not decrypt \(url.lastPathComponent) after \(Self.maxPasswordAttempts) attempts. The password may be wrong, or the archive may be damaged.")
                }

                let request = ArchivePasswordRequest(
                    url: url,
                    attempt: attempt
                )

                guard let password = await passwordResolver(request) else {
                    throw ArchiveError.passwordCancelled
                }

                archive.setPassword(password)
                continue
            }
            
            // Anything else is a real failure, not something a password fixes.
            throw ArchiveError.xadError(
                archive.lastError(),
                archive.describeLastError()
            )
        }
    }
    
    public func setNameEncoding(_ encoding: UInt) async throws {
        try await performXADOperationWithPasswordRetry {
            self.archive.setNameEncoding(encoding)
        }
    }
    
    public func numberOfEntries() async throws -> Int32 {
        try await performXADOperationWithPasswordRetry {
            let nrofEntries = self.archive.numberOfEntries()
            return nrofEntries
        }
    }
    
    public func name(ofEntry n: Int32) async throws -> String {
        try await performXADOperationWithPasswordRetry {
            let name = self.archive.name(ofEntry: n) ?? ""
            return name
        }
    }
    
    public func entryIsDirectory(_ n: Int32) async throws -> Bool {
        try await performXADOperationWithPasswordRetry {
            let isDir = self.archive.entryIsDirectory(n)
            return isDir
        }
    }
    
    public func entryHasSize(_ n: Int32) async throws -> Bool {
        try await performXADOperationWithPasswordRetry {
            let hasSize = self.archive.entryHasSize(n)
            return hasSize
        }
    }

    public func entryIsEncrypted(_ n: Int32) async throws -> Bool {
        try await performXADOperationWithPasswordRetry {
            self.archive.entryIsEncrypted(n)
        }
    }
    
    public func compressedSize(ofEntry n: Int32) async throws -> Int {
        try await performXADOperationWithPasswordRetry {
            let size = self.archive.compressedSize(ofEntry: n)
            return Int(size)
        }
    }
    
    public func uncompressedSize(ofEntry n: Int32) async throws -> Int {
        try await performXADOperationWithPasswordRetry {
            let size = self.archive.uncompressedSize(ofEntry: n)
            return Int(size)
        }
    }
    
    public func attributes(ofEntry n: Int32) async throws -> [AnyHashable : Any] {
        try await performXADOperationWithPasswordRetry {
            let attrs = self.archive.attributes(ofEntry: n) ?? [:]
            return attrs
        }
    }
    
    public func extractEntry(_ n: Int32, to: String) async throws {
        let result = try await performXADOperationWithPasswordRetry {
            let r = self.archive.extractEntry(n, to: to)
            return r
        }
        
        if result == false {
            throw ArchiveError.extractionFailed("Extraction failed for an unknown reason")
        }
    }
    
    public func extractEntries(_ entryset: IndexSet!, to: String) async throws {
        let result = try await performXADOperationWithPasswordRetry {
            let r = self.archive.extractEntries(entryset, to: to)
            return r
        }
        
        if result == false {
            throw ArchiveError.extractionFailed("Extraction failed for an unknown reason")
        }
    }
    
    public func extract(to: String) async throws {
        let result = try await performXADOperationWithPasswordRetry {
            let r = self.archive.extract(to: to)
            return r
        }
        
        if result == false {
            throw ArchiveError.extractionFailed("Extraction failed for an unknown reason")
        }
    }
    
    public func setDelegate(_ delegate: AnyObject?) {
        archive.setDelegate(delegate)
    }

    public func lastError() -> XADError {
        return archive.lastError()
    }
    
    public func describeLastError() -> String {
        return archive.describeLastError()
    }
}

/// Receives XADArchive's informal-delegate callbacks and relays byte
/// progress to the engine consumer; also answers the should-stop poll so
/// the cancel button aborts XAD extractions mid-flight. Only our delegate
/// object — vendored XADMaster stays untouched.
private final class XADExtractionProgressDelegate: NSObject, @unchecked Sendable {
    private let lock = NSLock()
    private let onProgress: ArchiveExtractionProgress
    /// Total for per-entry mode, from the items' listing sizes.
    private let totalBytes: Int64
    /// True when the whole-archive extraction runs — XAD then reports
    /// global counters itself and the per-entry callback is ignored.
    private let usesGlobalCounters: Bool
    private var baseBytes: Int64 = 0
    private var stopped = false

    init(onProgress: @escaping ArchiveExtractionProgress, totalBytes: Int64, usesGlobalCounters: Bool) {
        self.onProgress = onProgress
        self.totalBytes = totalBytes
        self.usesGlobalCounters = usesGlobalCounters
    }

    var wasStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    /// Called by the engine after an entry finished, so the next entry's
    /// per-entry byte counts continue from the right offset.
    func advanceBase(by bytes: Int64) {
        lock.lock()
        defer { lock.unlock() }
        baseBytes += Swift.max(0, bytes)
    }

    private func relay(_ completed: Int64, _ total: Int64) {
        if !onProgress(completed, total) {
            lock.lock()
            stopped = true
            lock.unlock()
        }
    }

    @objc(archiveExtractionShouldStop:)
    override func archiveExtractionShouldStop(_ archive: XADArchive!) -> Bool {
        wasStopped
    }

    @objc(archive:extractionProgressForEntry:bytes:of:)
    override func archive(_ archive: XADArchive!, extractionProgressForEntry n: Int32, bytes: off_t, of total: off_t) {
        guard !usesGlobalCounters else { return }
        lock.lock()
        let base = baseBytes
        lock.unlock()
        relay(base + Int64(bytes), totalBytes)
    }

    @objc(archive:extractionProgressBytes:of:)
    override func archive(_ archive: XADArchive!, extractionProgressBytes bytes: off_t, of total: off_t) {
        guard usesGlobalCounters else { return }
        relay(Int64(bytes), Int64(total))
    }
}

final actor ArchiveXadEngine: ArchiveEngine {
    private var statusContinuation: AsyncStream<EngineStatus>.Continuation?

    func statusStream() -> AsyncStream<EngineStatus> {
        AsyncStream { continuation in
            self.statusContinuation = continuation
            continuation.yield(.idle)
        }
    }
    
    private func emit(_ s: EngineStatus) {
        statusContinuation?.yield(s)
    }
    
    func cancel() async {
    }
    
    func loadArchive(
        url: URL,
        passwordResolver: @escaping ArchivePasswordResolver
    ) async throws -> ArchiveEngineLoadResult {
        let archive = try XADArchiveWithPasswordSupport(
            url: url,
            passwordResolver: passwordResolver
        )
        try await archive.setNameEncoding(NSUTF8StringEncoding)

        var entries: [UUID: ArchiveItem] = [:]
        var uncompressedSizeOverall: Int64 = 0
        var isEncrypted = false
        let numberOfEntries = try await archive.numberOfEntries()
        for index in 0..<numberOfEntries {
            // name
            let path = try await archive.name(ofEntry: index)
            let isDir = try await archive.entryIsDirectory(index)
            if try await archive.entryIsEncrypted(index) { isEncrypted = true }
            
            // tar archives (and similar) don't have a compressed size as they
            // just package up files.
            var compressedSize: Int = -1
            var uncompressedSize: Int = -1
            compressedSize = try await archive.compressedSize(ofEntry: index)
            if !isDir {
                if try await archive.entryHasSize(index) {
                    uncompressedSize = try await archive.uncompressedSize(ofEntry: index)
                } else {
                    uncompressedSize = try await archive.compressedSize(ofEntry: index)
                }
            }
            
            // get more attributes
            var modificationDate: Date?
            var posixPermissions: Int?
            let attributes = try await archive.attributes(ofEntry: index)
            if let dict = attributes as? [String: Any] {
                modificationDate = dict["NSFileModificationDate"] as? Date
                posixPermissions = dict["NSFilePosixPermissions"] as? Int
            }
            
            var name = path
            let parts = path.split(separator: "/")
            if let last = parts.last {
                name = String(last)
            }

            let entry = ArchiveItem(
                index: UInt32(index),
                name: name,
                virtualPath: path, // the name in the archive dictionary is usually the full path
                type: isDir ? .directory : .file,
                compressedSize: Int(compressedSize),
                uncompressedSize: Int(uncompressedSize),
                modificationDate: modificationDate,
                posixPermissions: posixPermissions
            )
            
            entries[entry.id] = entry
            
            uncompressedSizeOverall += Int64(entry.uncompressedSize)
        }
        
        emit(.done)
        
        return ArchiveEngineLoadResult(
            items: entries,
            hasTree: false,
            uncompressedSize: uncompressedSizeOverall,
            isEncrypted: isEncrypted
        )
    }
    
    func extract(
        items: [ArchiveItem],
        from url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver
    ) async throws -> ArchiveExtractionResult {
        try await extract(items: items, from: url, to: destination, passwordResolver: passwordResolver, onProgress: nil)
    }

    func extract(
        items: [ArchiveItem],
        from url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver,
        onProgress: ArchiveExtractionProgress?
    ) async throws -> ArchiveExtractionResult {
        let archive = try XADArchiveWithPasswordSupport(
            url: url,
            passwordResolver: passwordResolver
        )
        try await archive.setNameEncoding(NSUTF8StringEncoding)

        let totalBytes = items.reduce(Int64(0)) { $0 + Int64(Swift.max(0, $1.uncompressedSize)) }
        let progressDelegate = onProgress.map {
            XADExtractionProgressDelegate(onProgress: $0, totalBytes: totalBytes, usesGlobalCounters: false)
        }
        if let progressDelegate {
            archive.setDelegate(progressDelegate)
        }

        var urlsByItemID: [UUID: URL] = [:]

        for item in items {
            try Task.checkCancellation()
            guard let virtualPath = item.virtualPath else {
                throw ArchiveError.extractionFailed("Could not extract file: missing virtual path")
            }
            guard let itemIndex = item.index else {
                throw ArchiveError.extractionFailed("Could not extract file: missing index")
            }

            let resultUrl = destination.appendingPathComponent(virtualPath, isDirectory: item.type == .directory)

            do {
                try await archive.extractEntry(Int32(itemIndex), to: destination.path)
            } catch {
                // XAD creates the output file before it decodes, so a failure
                // (wrong password, corrupt data) leaves a truncated or empty
                // file that looks like a successful extraction. Remove it.
                try? FileManager.default.removeItem(at: resultUrl)
                // a should-stop answer makes XAD fail the entry — surface
                // it as cancellation, not as an extraction error
                if progressDelegate?.wasStopped == true {
                    throw CancellationError()
                }
                throw error
            }
            if progressDelegate?.wasStopped == true {
                throw CancellationError()
            }
            progressDelegate?.advanceBase(by: Int64(Swift.max(0, item.uncompressedSize)))

            urlsByItemID[item.id] = resultUrl
        }

        return ArchiveExtractionResult(urlsByItemID: urlsByItemID)
    }
    
    func extract(
        _ url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver
    ) async throws {
        try await extract(url, to: destination, passwordResolver: passwordResolver, onProgress: nil)
    }

    func extract(
        _ url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver,
        onProgress: ArchiveExtractionProgress?
    ) async throws {
        let archive = try XADArchiveWithPasswordSupport(
            url: url,
            passwordResolver: passwordResolver
        )
        try await archive.setNameEncoding(NSUTF8StringEncoding)

        let progressDelegate = onProgress.map {
            // whole-archive mode: XAD reports its own global byte counters
            XADExtractionProgressDelegate(onProgress: $0, totalBytes: 0, usesGlobalCounters: true)
        }
        if let progressDelegate {
            archive.setDelegate(progressDelegate)
        }

        do {
            try await archive.extract(
                to: destination.path
            )
        } catch {
            if progressDelegate?.wasStopped == true {
                throw CancellationError()
            }
            throw error
        }
        if progressDelegate?.wasStopped == true {
            throw CancellationError()
        }
    }
}
