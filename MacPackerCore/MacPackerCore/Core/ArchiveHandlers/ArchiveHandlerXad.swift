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

struct XadArchiveEntry {
    let index: Int32
    let name: String // "file1"
    let path: String // "folder/file1"
    let type: ArchiveItemType
    let compressedSize: Int?
    let uncompressedSize: Int?
    let modificationDate: Date?
    let posixPermissions: Int?
    
    init(
        index: Int32,
        path: String,
        type: ArchiveItemType,
        compressedSize: Int?,
        uncompressedSize: Int?,
        modificationDate: Date?,
        posixPermissions: Int?
    ) {
        self.index = index
        self.path = path
        self.type = type
        self.compressedSize = compressedSize
        self.uncompressedSize = uncompressedSize
        self.modificationDate = modificationDate
        self.posixPermissions = posixPermissions
        
        let parts = path.split(separator: "/")
        if let last = parts.last {
            self.name = String(last)
        } else {
            self.name = path
        }
    }
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
        typeRegistry.register(typeID: .xz, capabilities: [.view, .extract], handler: handler)
        typeRegistry.register(typeID: .Z, capabilities: [.view, .extract], handler: handler)
//        typeRegistry.register(typeID: .zip, capabilities: [.view, .extract], handler: handler)
        typeRegistry.register(typeID: .zipx, capabilities: [.view, .extract], handler: handler)
    }
    
    public override func contents(
        of url: URL
    ) throws -> [ArchiveItem] {
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
        return entries
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
        archive.setNameEncoding(NSUTF8StringEncoding)
        
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
                            index: Int(index),
                            name: npc.name,
                            virtualPath: archivePath + "/" + npc.name,
                            type: .directory
                            ))
                    }
                } else {
                    if let fileName = npc.name.components(separatedBy: "/").last {
                        result.append(ArchiveItem(
                            index: Int(index),
                            name: fileName,
                            virtualPath: name,
                            type: .file,
                            compressedSize: Int(compressedSize),
                            uncompressedSize: Int(uncompressedSize),
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
