//
//  Archive7ZipEngineNew.swift
//  Modules
//
//  Created by Stephan Arenswald on 27.03.26.
//

import Foundation
import Swift7zip

final actor Archive7ZipEngine: ArchiveEngine {
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
        let szip = try SevenZipArchive(url: url)
        
        var items: [UUID: ArchiveItem] = [:]
        var uncompressedSizeOverall: Int64 = 0
        var idToUUIDMap: [UInt32: UUID] = [:]
        
        try szip.entries.forEach { entry in
            var name = entry.path
            let parts = entry.path.split(separator: "/")
            if let last = parts.last {
                name = String(last)
            }
            
            let item: ArchiveItem = .init(
                index: entry.index,
                name: name,
                virtualPath: entry.path,
                type: entry.isDirectory ? .directory : .file,
                parent: nil,
                compressedSize: Int(entry.packedSize),
                uncompressedSize: Int(entry.size),
                modificationDate: entry.modificationDate,
                posixPermissions: entry.posixPermissions.map { Int($0) })
            items[item.id] = item
            idToUUIDMap[entry.index] = item.id
            
            uncompressedSizeOverall += Int64(entry.size)
        }
        
        if szip.isTree {
            // The file type (usually disk images) already provide the hierarchy.
            // So there is no need to recalculate this later. Just one pass here.
            try szip.entries.forEach { entry in
                let index = entry.index
                if
                    // the item itself
                    let uuid = idToUUIDMap[index],
                    let item = items[uuid],
                    // the parent item to make sure the parent knows its children
                    let parentIndex = entry.parentIndex,
                    let parentUUID = idToUUIDMap[parentIndex],
                    let parentItem = items[parentUUID]
                {
                    item.parent = idToUUIDMap[parentIndex]
                    parentItem.addChild(uuid)
                }
            }
        }
        
        return ArchiveEngineLoadResult(
            items: items,
            hasTree: szip.isTree,
            uncompressedSize: uncompressedSizeOverall
        )
    }
    
    func extract(
        items: [ArchiveItem],
        from url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver
    ) async throws -> ArchiveExtractionResult {
        guard items.isEmpty == false else {
            throw ArchiveError.extractionFailed("No items to extract")
        }
        
        // get the list of indices first
        var indices: [UInt32: UUID] = [:]
        for item in items {
            if let index = item.index {
                indices[index] = item.id
            }
        }
        let sorted = indices.keys.sorted { $0 < $1 }
        
        let szip = try SevenZipArchive(url: url)
        
        var attempt = 0
        // The loop is used to allow multiple tries when there is no password
        // give or the password is wrong
        // TODO: Change from while true loop to a loop with a real end condition
        while true {
            do {
                let extractedEntries: [UInt32: URL] = try szip.extract(indices: sorted, to: destination)
                
                let urlsByItemID: [UUID: URL] = Dictionary(
                    uniqueKeysWithValues: extractedEntries.compactMap { (index, url) in
                        guard let uuid = indices[index] else { return nil }
                        return (uuid, url)
                    }
                )
                
                let result = ArchiveExtractionResult(urlsByItemID: urlsByItemID)
                
                return result
                
            } catch SevenZipError.passwordMissing {
                attempt += 1
                
                let request = ArchivePasswordRequest(
                    url: url,
                    attempt: attempt
                )
                
                guard let password = await passwordResolver(request) else {
                    throw ArchiveError.passwordCancelled
                }
                
                szip.setPassword(password)
                continue
            }
        }
    }
    
    func extract(
        _ url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver
    ) async throws {
        
    }
}
