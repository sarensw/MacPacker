//
//  XADMasterSwiftInternal.swift
//  MacPacker
//
//  This is a copy of the XADMasterSwift file from the XADMasterSwift
//  repo. The difference is that there is no cache for the currently
//  active archive. From MacPacker point-of-view a handler is stateless.
//
//  Created by Stephan Arenswald on 06.09.25.
//

import Foundation
import XADMaster

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

class XadMasterHandler {
    
    public func listContents(of path: String) throws -> [XadArchiveEntry] {
        guard let archive = XADArchive(file: path) else {
            throw NSError(domain: "XADMasterSwift", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create archive"])
        }
        
        if archive.isEncrypted() && archive.password()!.isEmpty {
            throw NSError(domain: "XADMasterSwift", code: 2, userInfo: [NSLocalizedDescriptionKey: "Password required"])
        }

        var entries: [XadArchiveEntry] = []
        for index in 0..<archive.numberOfEntries() {
            // name
            guard let name = archive.name(ofEntry: index) else { continue }
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

            let entry = XadArchiveEntry(
                index: index,
                path: name, // the name in the archive dictionary is usually the full path
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
    
    public func extract(
        archive: Archive,
        items: [ArchiveItem],
        to path: String
    ) throws {
        guard let archive = XADArchive(file: archive.url.path) else {
            throw NSError(domain: "XADMasterSwift", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create archive"])
        }
        
        for item in items {
            guard let index = item.index else {
                continue
            }
            
            archive.extractEntry(
                index,
                to: path
            )
        }
    }
    
    public func extractAll(
        archive: Archive,
        to path: String
    ) throws {
        guard let archive = XADArchive(file: archive.url.path) else {
            throw NSError(domain: "XADMasterSwift", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create archive"])
        }
        
        archive.extract(
            to: path
        )
    }
}
