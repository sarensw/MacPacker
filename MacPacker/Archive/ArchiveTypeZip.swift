//
//  ArchiveZip.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 24.09.23.
//

import Foundation
import SWCompression
import ZIPFoundation

typealias ZipArchive = ZIPFoundation.Archive

class ArchiveTypeZip: IArchiveType {
    var ext: String = "zip"
    
    /// Returns the content of the zip file in form of FileItems. There is no need to extract the zip
    /// file because it allows us to peek into the zip file and get the content.
    /// - Parameters:
    ///   - path: Path to the zip file
    ///   - archivePath: Path within the zip archive to return
    /// - Returns: Items in the archive with the given path
    public func content(path: URL, archivePath: String) throws -> [ArchiveItem] {
        var result: [ArchiveItem] = []
        var dirs: [String] = []
        
        do {
            if let data = try? Data(contentsOf: path, options: .mappedIfSafe) {
                print("data loaded")
                
                let entries = try ZipContainer.open(container: data)
                entries.forEach { zipEntry in
                    if let npc = nextPathComponent(
                        after: archivePath,
                        in: zipEntry.info.name,
                        isDirectoryHint: zipEntry.info.type == .directory
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
                                    data: zipEntry.data))
                            }
                        } else {
                            if let name = npc.name.components(separatedBy: "/").last {
                                result.append(ArchiveItem(
                                    name: name,
                                    type: .file,
                                    virtualPath: zipEntry.info.name,
                                    data: zipEntry.data))
                            }
                        }
                    }
                }
            }
        } catch {
            print("zip.content ran in error")
            print(error)
        }
        
        return result
    }
    
    func extractFileToTemp(path: URL, item: ArchiveItem) -> URL? {
        if let tempUrl = createTempDirectory() {
            
            let extractedFilePathName = tempUrl.path.appendingPathComponent(
                item.name,
                isDirectory: false)
            FileManager.default.createFile(
                atPath: extractedFilePathName.path,
                contents: item.data)
            
            return extractedFilePathName
        }
        
        return nil
    }
    
    func extractToTemp(path: URL) -> URL? {
        return nil
    }
    
    func save(to url: URL, items: [ArchiveItem]) throws {
        let fileExists = FileManager.default.fileExists(atPath: url.path)
        let archive = try ZipArchive(
            url: url,
            accessMode: fileExists ? .update : .create)
        
        for item in items {
            if let path = item.path {
                try archive.addEntry(
                    with: path.lastPathComponent,
                    relativeTo: path.deletingLastPathComponent())
            }
        }
    }
}
