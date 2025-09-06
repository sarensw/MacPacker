//
//  ArchiveHandlerXad.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 05.09.25.
//

import Foundation
import XADMaster
import XADMasterSwift

enum XADMasterEntryType {
    case directory
    case file
}

class ArchiveHandlerXad: ArchiveHandler {
    
    static func register() {
        let registry = ArchiveHandlerRegistry.shared
        let handler = ArchiveHandlerXad()
        
        registry.register(ext: "rar", handler: handler)
        registry.register(ext: "lzh", handler: handler)
        registry.register(ext: "7z", handler: handler)
        registry.register(ext: "tar", handler: handler)
    }
    
    override func content(
        archiveUrl: URL,
        archivePath: String
    ) throws -> [ArchiveItem] {
        var result: [ArchiveItem] = []
        var dirs: [String] = []
        
        guard let archive = XADArchive(file: archiveUrl.path) else {
            Logger.error(
                "Failed to open archive \(archiveUrl.path)"
                )
            return []
        }
        
        for index in 0..<archive.numberOfEntries() {
            let name = archive.name(ofEntry: index) ?? "<unknown>"
            let size = archive.size(ofEntry: index)
            let type: XADMasterEntryType = archive.entryIsDirectory(index) ? .directory : .file
            
            if let npc = nextPathComponent(
                after: archivePath,
                in: name,
                isDirectoryHint: type == .directory
            ) {
                if npc.isDirectory {
                    if dirs.contains(where: { $0 == npc.name }) {
                        // added already, ignore
                    } else {
                        dirs.append(npc.name)
                        
                        result.append(ArchiveItem(
                            name: npc.name,
                            type: .directory,
                            virtualPath: archivePath + "/" + npc.name,
                            size: nil,
                            data: nil))
                    }
                } else {
                    if let fileName = npc.name.components(separatedBy: "/").last {
                        result.append(ArchiveItem(
                            name: fileName,
                            type: .file,
                            virtualPath: name,
                            size: Int(size),
                            index: Int(index)
                        ))
                    }
                }
            }
        }
        
        return result
    }
    
    override func extractFileToTemp(path: URL, item: ArchiveItem) -> URL? {
        guard let index = item.index else { return nil }
        guard let virtualPath = item.virtualPath else { return nil }
        
        if let tempDirectory = createTempDirectory() {
            do {
                try XADMasterSwift.extractFile(
                    at: path.path,
                    entryIndex: index,
                    to: tempDirectory.path.path
                )
                
                let extractedFileUrl = tempDirectory.path.appendingPathComponent(virtualPath, isDirectory: false)
                
                return extractedFileUrl
            } catch {
                print(error)
            }
        }
        return nil
    }
}
