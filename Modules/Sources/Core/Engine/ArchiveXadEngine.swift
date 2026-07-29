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
        guard let archive = XADArchive(file: url.path) else {
            throw NSError(domain: "XADMasterSwift", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create archive"])
        }
        self.url = url
        self.archive = archive
        self.passwordResolver = passwordResolver
    }
    
    /// How many passwords a single operation will ask for before giving up.
    /// A resolver that keeps answering with the same wrong password (a stale
    /// cache, a scripted caller) would otherwise spin this loop forever at full
    /// CPU without ever surfacing an error.
    private static let maxPasswordAttempts = 20

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

            // failed, but because password is wrong / needed > ask user
            if error == 15 {
                attempt += 1

                guard attempt <= Self.maxPasswordAttempts else {
                    throw ArchiveError.extractionFailed(
                        "The password is incorrect (\(Self.maxPasswordAttempts) attempts)")
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
            
            // Error code is not 0 (success) and 15 (password missing), therefore,
            // throw for now. We might handle other error codes in future
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
        let numberOfEntries = try await archive.numberOfEntries()
        for index in 0..<numberOfEntries {
            // name
            let path = try await archive.name(ofEntry: index)
            let isDir = try await archive.entryIsDirectory(index)
            
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
            uncompressedSize: uncompressedSizeOverall
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
