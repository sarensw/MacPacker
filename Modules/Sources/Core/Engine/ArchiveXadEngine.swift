//
//  ArchiveXadEngine.swift
//  Modules
//
//  Created by Stephan Arenswald on 25.11.25.
//

import Foundation
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

public final class ArchiveXadEngine: ArchiveEngine {
    
    public init() {}
    
    public func loadArchive(
        url: URL
    ) async throws -> [ArchiveItem] {
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
    
    public func extract(
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
        let lastErrorMessage = archive.describeLastError()
        print(lastErrorMessage)
        
        if result == true {
            print("1: \(destination.startAccessingSecurityScopedResource())")
//            let resultUrl = destination.appending(component: virtualPath)
            let resultUrl = destination.appendingPathComponent(virtualPath, isDirectory: false)
            print("2: \(resultUrl.startAccessingSecurityScopedResource())")
            return resultUrl
        }
        
        return nil
    }
}
