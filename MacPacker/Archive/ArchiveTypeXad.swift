//
//  ArchiveTypeXad.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 19.07.25.
//

import Foundation
import XADMaster
import XADMasterSwift

enum XADMasterEntryType {
    case directory
    case file
}

class XADMasterEntry {
    let name: String
    let size: Int32?
    let type: XADMasterEntryType
    let index: Int?
    
    init(name: String, size: Int32?, type: XADMasterEntryType, index: Int?) {
        self.name = name
        self.size = size
        self.type = type
        self.index = index
    }
    
    var debugDescription: String {
        return "XADMasterEntry(\(index): \(name), \(type), size: \(size ?? 0))"
    }
}

class XADMasterSwift2 {
//    private static var currentArchive: XADArchive?

    public static func extractArchive(at path: String, to destination: String) throws {
        guard let archive = XADArchive(file: path) else {
            throw NSError(domain: "XADMasterSwift", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create archive"])
        }
//        currentArchive = archive
        try archive.extract(to: destination)
    }

    public static func listContents(of path: String) throws -> [XADMasterEntry] {
        guard let archive = XADArchive(file: path) else {
            throw NSError(domain: "XADMasterSwift", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create archive"])
        }
//        currentArchive = archive

        if archive.isEncrypted() && (archive.password == nil || archive.password()!.isEmpty) {
            throw NSError(domain: "XADMasterSwift", code: 2, userInfo: [NSLocalizedDescriptionKey: "Password required"])
        }

        var contents: [XADMasterEntry] = []
        for index in 0..<archive.numberOfEntries() {
            let name = archive.name(ofEntry: index)
            let size = archive.size(ofEntry: index)
            let type: XADMasterEntryType = archive.entryIsDirectory(index) ? .directory : .file
            
            let entry = XADMasterEntry(
                name: name ?? "<unknown>",
                size: size,
                type: type,
                index: Int(index)
            )
            print(entry.debugDescription)
            contents.append(entry)
        }
        return contents
    }

    public static func extractFile(at path: String, entryIndex: Int, to destination: String) throws {
        guard let archive = XADArchive(file: path) else {
            throw NSError(domain: "XADMasterSwift", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create archive"])
        }
//        currentArchive = archive

        try archive.extractEntry(Int32(entryIndex), to: destination)
//        try archive.extractEntry(Int32(entryIndex), to: destination, deferDirectories: true)
    }

    public static func setPassword(for path: String, password: String) throws {
        guard let archive = XADArchive(file: path) else {
            throw NSError(domain: "XADMasterSwift", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create archive"])
        }
//        currentArchive = archive

        archive.setPassword(password)
    }

    public static func getArchiveFormat(of path: String) throws -> String {
        guard let archive = XADArchive(file: path) else {
            throw NSError(domain: "XADMasterSwift", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create archive"])
        }
//        currentArchive = archive

        return archive.formatName()
    }
}

class ArchiveTypeXad: IArchiveType {
    var ext: String = "rar"
    
    func content(path: URL, archivePath: String) throws -> [ArchiveItem] {
        var result: [ArchiveItem] = []
        var dirs: [String] = []
        
        do {
            let entries = try XADMasterSwift2.listContents(of: path.path)
            entries.forEach { tarEntry in
                if let npc = nextPathComponent(
                    after: archivePath,
                    in: tarEntry.name,
                    isDirectoryHint: tarEntry.type == .directory
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
                        if let name = npc.name.components(separatedBy: "/").last {
                            result.append(ArchiveItem(
                                name: name,
                                type: .file,
                                virtualPath: tarEntry.name,
                                size: tarEntry.size == nil ? nil : Int(tarEntry.size!),
                                index: tarEntry.index
                            ))
                        }
                    }
                }
            }
        } catch {
            print("tar.content ran in error")
            print(error)
        }
        
        return result
    }
    
    func extractToTemp(path: URL) -> URL? {
        return nil
    }
    
    func extractFileToTemp(path: URL, item: ArchiveItem) -> URL? {
        guard let index = item.index else { return nil }
        guard let virtualPath = item.virtualPath else { return nil }
        
        if let tempDirectory = createTempDirectory() {
            do {
                try XADMasterSwift.extractFile(
                    at: path.path,
                    entryIndex: index,
                    to: tempDirectory.path.path)
                
                let extractedFileUrl = tempDirectory.path.appendingPathComponent(virtualPath, isDirectory: false)
                
                return extractedFileUrl
            } catch {
                print(error)
            }
        }
        return nil
    }
    
    func save(to: URL, items: [ArchiveItem]) throws {
    }
    
    
}
