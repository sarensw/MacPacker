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
    
    func performXADOperationWithPasswordRetry<T>(
        operation: () -> T
    ) async throws -> T {
        var attempt = 0

        while true {
            archive.clearLastError()
            
            let value = operation()
            let error = archive.lastError()
            
            // success
            if error == 0 {
                return value
            }
            
            // failed, but because password is wrong / needed > ask user
            if error == 15 {
                attempt += 1
                
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
            archive.setNameEncoding(encoding)
        }
    }
    
    public func numberOfEntries() async throws -> Int32 {
        try await performXADOperationWithPasswordRetry {
            let nrofEntries = archive.numberOfEntries()
            return nrofEntries
        }
    }
    
    public func name(ofEntry n: Int32) async throws -> String {
        try await performXADOperationWithPasswordRetry {
            let name = archive.name(ofEntry: n) ?? ""
            return name
        }
    }
    
    public func entryIsDirectory(_ n: Int32) async throws -> Bool {
        try await performXADOperationWithPasswordRetry {
            let isDir = archive.entryIsDirectory(n)
            return isDir
        }
    }
    
    public func entryHasSize(_ n: Int32) async throws -> Bool {
        try await performXADOperationWithPasswordRetry {
            let hasSize = archive.entryHasSize(n)
            return hasSize
        }
    }
    
    public func compressedSize(ofEntry n: Int32) async throws -> Int {
        try await performXADOperationWithPasswordRetry {
            let size = archive.compressedSize(ofEntry: n)
            return Int(size)
        }
    }
    
    public func uncompressedSize(ofEntry n: Int32) async throws -> Int {
        try await performXADOperationWithPasswordRetry {
            let size = archive.uncompressedSize(ofEntry: n)
            return Int(size)
        }
    }
    
    public func attributes(ofEntry n: Int32) async throws -> [AnyHashable : Any] {
        try await performXADOperationWithPasswordRetry {
            let attrs = archive.attributes(ofEntry: n) ?? [:]
            return attrs
        }
    }
    
    public func extractEntry(_ n: Int32, to: String) async throws {
        let result = try await performXADOperationWithPasswordRetry {
            let r = archive.extractEntry(n, to: to)
            return r
        }
        
        if result == false {
            throw ArchiveError.extractionFailed("Extraction failed for an unknown reason")
        }
    }
    
    public func extract(to: String) async throws {
        let result = try await performXADOperationWithPasswordRetry {
            let r = archive.extract(to: to)
            return r
        }
        
        if result == false {
            throw ArchiveError.extractionFailed("Extraction failed for an unknown reason")
        }
    }
    
    public func lastError() -> XADError {
        return archive.lastError()
    }
    
    public func describeLastError() -> String {
        return archive.describeLastError()
    }
}

final actor ArchiveXadEngine: ArchiveEngine {
    private var statusContinuation: AsyncStream<EngineStatus>.Continuation?
    private lazy var status: AsyncStream<EngineStatus> = {
        AsyncStream(bufferingPolicy: .bufferingNewest(50)) { continuation in
            self.statusContinuation = continuation
            continuation.yield(.idle)
        }
    }()
    
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

        var entries: [ArchiveItem] = []
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
            if try await archive.entryHasSize(index) {
                uncompressedSize = try await archive.uncompressedSize(ofEntry: index)
            } else {
                uncompressedSize = try await archive.compressedSize(ofEntry: index)
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
                index: Int(index),
                name: name,
                virtualPath: path, // the name in the archive dictionary is usually the full path
                type: isDir ? .directory : .file,
                compressedSize: Int(compressedSize),
                uncompressedSize: Int(uncompressedSize),
                modificationDate: modificationDate,
                posixPermissions: posixPermissions
            )
            
            entries.append(entry)
            uncompressedSizeOverall += Int64(entry.uncompressedSize)
        }
        
        emit(.done)
        
        return ArchiveEngineLoadResult(items: entries, uncompressedSize: uncompressedSizeOverall)
    }
    
    func extract(
        item: ArchiveItem,
        from url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver
    ) async throws -> URL {
        guard let virtualPath = item.virtualPath else {
            throw ArchiveError.extractionFailed("Could not extract file: missing virtual path")
        }
        
        let archive = try XADArchiveWithPasswordSupport(
            url: url,
            passwordResolver: passwordResolver
        )
        try await archive.setNameEncoding(NSUTF8StringEncoding)

        try await archive.extractEntry(Int32(item.index), to: destination.path)
        
        // In case this is a directory, we have to traverse down to extract all items
        // as XAD doesn't do this automatically. In this case, we can ignore the result
        // url as the top level url is the only thing that needs to be returned.
        // TODO: NOTE: This will stop at nested archives and not extract their content.
        for child in item.children ?? [] {
            _ = try? await extract(item: child, from: url, to: destination, passwordResolver: passwordResolver)
        }
        
        print("1: \(destination.startAccessingSecurityScopedResource())")
        let resultUrl = destination.appendingPathComponent(virtualPath, isDirectory: false)
        print("2: \(resultUrl.startAccessingSecurityScopedResource())")
        return resultUrl
    }
    
    func extract(
        _ url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver
    ) async throws {
        let archive = try XADArchiveWithPasswordSupport(
            url: url,
            passwordResolver: passwordResolver
        )
        try await archive.setNameEncoding(NSUTF8StringEncoding)
        
        try await archive.extract(
            to: destination.path
        )
    }
}
