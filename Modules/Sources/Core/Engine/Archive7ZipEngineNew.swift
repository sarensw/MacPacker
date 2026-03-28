//
//  Archive7ZipEngineNew.swift
//  Modules
//
//  Created by Stephan Arenswald on 27.03.26.
//

import Foundation
import Swift7zip

final actor Archive7ZipEngineNew: ArchiveEngine {
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
        let szip = try SevenZipArchive(url: url)
        
        var items: [ArchiveItem] = []
        var uncompressedSizeOverall: Int64 = 0
        
        try szip.entries.forEach { entry in
            var name = entry.path
            let parts = entry.path.split(separator: "/")
            if let last = parts.last {
                name = String(last)
            }
            
            let item: ArchiveItem = .init(
                index: Int(entry.index),
                name: name,
                virtualPath: entry.path,
                type: entry.isDirectory ? .directory : .file,
                parent: nil,
                compressedSize: Int(entry.packedSize),
                uncompressedSize: Int(entry.size),
                modificationDate: entry.modificationDate,
                posixPermissions: entry.posixPermissions.map { Int($0) })
            items.append(item)
            
            uncompressedSizeOverall += Int64(entry.size)
        }
        
        return ArchiveEngineLoadResult(
            items: items,
            uncompressedSize: uncompressedSizeOverall
        )
    }
    
    func extract(
        item: ArchiveItem,
        from url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver
    ) async throws -> URL {
        guard
            let index = UInt32(exactly: item.index)
        else {
            throw ArchiveError.extractionFailed("Invalid index given: \(String(describing: item.index))")
        }
        guard let virtualPath = item.virtualPath else {
            throw ArchiveError.extractionFailed("Item has no virtual path")
        }
        let szip = try SevenZipArchive(url: url)
        
        var attempt = 0
        while true {
            do {
                try szip.extract(index: index, to: destination)
                break
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
        
        let extractedFilePathName = destination.appendingPathComponent(virtualPath, isDirectory: false)
        return extractedFilePathName
    }
    
    func extract(
        _ url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver
    ) async throws {
        
    }
}
