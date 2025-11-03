//
//  ArchiveHandlerXad.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 05.09.25.
//

import Foundation
import UniformTypeIdentifiers
import XADMaster

enum XADMasterEntryType {
    case directory
    case file
}

public class ArchiveHandlerXad: ArchiveHandler {
    
    public static func register() {
        let handler = ArchiveHandlerXad()
        
        let typeRegistry = ArchiveTypeRegistry.shared
        
        typeRegistry.register(typeID: .`7zip`, capabilities: [.view, .extract], handler: handler)
        typeRegistry.register(typeID: .bzip2, capabilities: [.view, .extract], handler: handler)
        typeRegistry.register(typeID: .cab, capabilities: [.view, .extract], handler: handler)
        typeRegistry.register(typeID: .cpio, capabilities: [.view, .extract], handler: handler)
        typeRegistry.register(typeID: .gzip, capabilities: [.view, .extract], handler: handler)
        typeRegistry.register(typeID: .iso, capabilities: [.view, .extract], handler: handler)
        typeRegistry.register(typeID: .lha, capabilities: [.view, .extract], handler: handler)
        typeRegistry.register(typeID: .lzx, capabilities: [.view, .extract], handler: handler)
        typeRegistry.register(typeID: .rar, capabilities: [.view, .extract], handler: handler)
        typeRegistry.register(typeID: .sea, capabilities: [.view, .extract], handler: handler)
        typeRegistry.register(typeID: .sit, capabilities: [.view, .extract], handler: handler)
        typeRegistry.register(typeID: .sitx, capabilities: [.view, .extract], handler: handler)
        typeRegistry.register(typeID: .tar, capabilities: [.view, .extract], handler: handler)
        typeRegistry.register(typeID: .`tar.bz2`, capabilities: [.view, .extract], handler: handler)
        typeRegistry.register(typeID: .`tar.gz`, capabilities: [.view, .extract], handler: handler)
        typeRegistry.register(typeID: .`tar.xz`, capabilities: [.view, .extract], handler: handler)
        typeRegistry.register(typeID: .xz, capabilities: [.view, .extract], handler: handler)
        typeRegistry.register(typeID: .Z, capabilities: [.view, .extract], handler: handler)
        typeRegistry.register(typeID: .zip, capabilities: [.view, .extract], handler: handler)
        typeRegistry.register(typeID: .zipx, capabilities: [.view, .extract], handler: handler)
    }
    
    public override func content(
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
                            index: Int(index)))
                    }
                } else {
                    if let fileName = npc.name.components(separatedBy: "/").last {
                        result.append(ArchiveItem(
                            name: fileName,
                            type: .file,
                            virtualPath: name,
                            compressedSize: Int(compressedSize),
                            uncompressedSize: Int(uncompressedSize),
                            index: Int(index),
                            modificationDate: modificationDate,
                            posixPermissions: posixPermissions
                        ))
                    }
                }
            }
        }
        
        return result
    }
    
    public override func extractFileToTemp(path: URL, item: ArchiveItem) -> URL? {
        guard let index = item.index else { return nil }
        guard let virtualPath = item.virtualPath else { return nil }
        
        if let tempDirectory = createTempDirectory() {
            do {
                try XADMasterSwiftInternal.extractFile(
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
    
    public override func extract(
        archiveUrl: URL,
        archiveItem: ArchiveItem,
        to url: URL
    ) {
        guard let index = archiveItem.index else {
            Logger.error("Could not extract file: missing index")
            return
        }
        
        do {
            try XADMasterSwiftInternal.extractFile(
                at: archiveUrl.path,
                entryIndex: index,
                to: url.path
            )
        } catch {
            Logger.error(error.localizedDescription)
        }
    }
    
    public override func extract(
        archiveUrl: URL,
        to url: URL
    ) {
        do {
            try XADMasterSwiftInternal.extractArchive(
                at: archiveUrl.path,
                to: url.path
            )
        } catch {
            Logger.error(error.localizedDescription)
        }
    }
}
