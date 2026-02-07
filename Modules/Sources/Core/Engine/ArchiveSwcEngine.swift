//
//  ArchiveSwcEngine.swift
//  Modules
//
//  Created by Stephan Arenswald on 14.12.25.
//

import Foundation
import SWCompression

final actor ArchiveSwcEngine: ArchiveEngine {
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
    
    private func stripFileExtension( _ filename: String ) -> String {
        var components = filename.components(separatedBy: ".")
        guard components.count > 1 else { return filename }
        components.removeLast()
        return components.joined(separator: ".")
    }
    
    func loadArchive(url: URL) async throws -> ArchiveEngineLoadResult {
        let name = stripFileExtension(url.lastPathComponent)
        
        emit(.done)
        
        return ArchiveEngineLoadResult(
            items: [ArchiveItem(name: String(name), virtualPath: name, type: .file)],
            uncompressedSize: 0
        )
    }
    
    func extract(item: ArchiveItem, from url: URL, to destination: URL) async throws -> URL? {
        let sourceFileName = url.lastPathComponent
        let extractedFileName = stripFileExtension(sourceFileName)
        let extractedFilePathName = destination.appendingPathComponent(extractedFileName, isDirectory: false)
        
        do {
            if let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
                let decompressedData = try LZ4.decompress(data: data)
                
                FileManager.default.createFile(atPath: extractedFilePathName.path, contents: decompressedData)
                
                return extractedFilePathName
            } else {
                Logger.error("Could not decompress archive")
            }
        } catch {
            Logger.error(error.localizedDescription)
        }
        
        return nil
    }
    
    func extract(_ url: URL, to destination: URL) async throws {
        let sourceFileName = url.lastPathComponent
        let extractedFileName = stripFileExtension(sourceFileName)
        let extractedFilePathName = url.appendingPathComponent(extractedFileName, isDirectory: false)
        
        do {
            if let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
                let decompressedData = try LZ4.decompress(data: data)
                
                FileManager.default.createFile(atPath: extractedFilePathName.path, contents: decompressedData)
            } else {
                Logger.error("Could not decompress archive")
            }
        } catch {
            Logger.error(error.localizedDescription)
        }
    }
    
    
}
