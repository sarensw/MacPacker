//
//  ArchiveXadEngine.swift
//  Modules
//
//  Created by Stephan Arenswald on 25.11.25.
//

import Foundation
import XADMaster

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
    
    func loadArchive(url: URL) async throws -> [ArchiveItem] {
        guard let archive = XADArchive(file: url.path) else {
            throw NSError(domain: "XADMasterSwift", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create archive"])
        }
        archive.setNameEncoding(NSUTF8StringEncoding)
        
        if archive.isEncrypted() && archive.password()!.isEmpty {
            throw NSError(domain: "XADMasterSwift", code: 2, userInfo: [NSLocalizedDescriptionKey: "Password required"])
        }

        var entries: [ArchiveItem] = []
        for index in 0..<archive.numberOfEntries() {
            // name
            guard let path = archive.name(ofEntry: index) else { continue }
            let isDir = archive.entryIsDirectory(index)
            
            // tar archives (and similar) don't have a compressed size as they
            // just package up files.
            var compressedSize: Int = -1
            var uncompressedSize: Int = -1
            compressedSize = Int(archive.compressedSize(ofEntry: index))
            if archive.entryHasSize(index) {
                uncompressedSize = Int(archive.uncompressedSize(ofEntry: index))
            } else {
                uncompressedSize = Int(archive.compressedSize(ofEntry: index))
            }
            
            // get more attributes
            var modificationDate: Date?
            var posixPermissions: Int?
            let attributes = archive.attributes(ofEntry: index)
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
        }
        
        emit(.done)
        
        return entries
    }
    
    func extract(
        item: ArchiveItem,
        from url: URL,
        to destination: URL
    ) async throws -> URL? {
        guard let index = item.index else {
            Logger.error("Could not extract file: missing index")
            return nil
        }
        
        guard let virtualPath = item.virtualPath else {
            Logger.error("Could not extract file: missing virtual path")
            return nil
        }
        
        guard let archive = XADArchive(file: url.path) else {
            Logger.error("Could not create XADArchive")
            return nil
        }
        archive.setNameEncoding(NSUTF8StringEncoding)

        let result = archive.extractEntry(Int32(index), to: destination.path)
//        let lastErrorMessage = archive.describeLastError()
        
        // In case this is a directory, we have to traverse down to extract all items
        // as XAD doesn't do this automatically. In this case, we can ignore the result
        // url as the top level url is the only thing that needs to be returned.
        // TODO: NOTE: This will stop at nested archives and not extract their content.
        for child in item.children ?? [] {
            _ = try? await extract(item: child, from: url, to: destination)
        }
        
        if result == true {
            print("1: \(destination.startAccessingSecurityScopedResource())")
            let resultUrl = destination.appendingPathComponent(virtualPath, isDirectory: false)
            print("2: \(resultUrl.startAccessingSecurityScopedResource())")
            return resultUrl
        }
        
        return nil
    }
    
    func extract(_ url: URL, to destination: URL) async throws {
        guard let archive = XADArchive(file: url.path) else {
            throw NSError(domain: "XADMasterSwift", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create archive"])
        }
        archive.setNameEncoding(NSUTF8StringEncoding)
        
        let result = archive.extract(
            to: destination.path
        )
        
        if result == false {
            let lastError = archive.lastError()
            let lastErrorMessage = archive.describeLastError()
            
            throw ArchiveError.extractionFailed("\(lastError) \(String(describing: lastErrorMessage))")
        }
    }
}
