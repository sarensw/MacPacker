//
//  ArchiveType7zip.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 27.11.23.
//

import Foundation
import SWCompression

class ArchiveType7zip: IArchiveType {
    var ext: String = "7z"
    
    /// Returns the content of the 7zip file in form of FileItems. There is no need to extract the 7zip
    /// file because it allows us to peek into the 7zip file and get the content.
    /// - Parameters:
    ///   - path: Path to the 7zip file
    ///   - archivePath: Path within the 7zip archive to return
    /// - Returns: Items in the archive with the given path
    public func content(path: URL, archivePath: String) throws -> [ArchiveItem] {
        var result: [ArchiveItem] = []
        var dirs: [String] = []
        
        do {
            if let data = try? Data(contentsOf: path, options: .mappedIfSafe) {
                print("data loaded")
                
                let entries = try SevenZipContainer.open(container: data)
                entries.forEach { szEntry in
                    if let npc = nextPathComponent(
                        after: archivePath,
                        in: szEntry.info.name,
                        isDirectoryHint: szEntry.info.type == .directory
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
                                    data: szEntry.data))
                            }
                        } else {
                            if let name = npc.name.components(separatedBy: "/").last {
                                result.append(ArchiveItem(
                                    name: name,
                                    type: .file,
                                    virtualPath: szEntry.info.name,
                                    data: szEntry.data))
                            }
                        }
                    }
                }
            }
        } catch {
            print("7z.content ran in error")
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
    
    func save(to: URL, items: [ArchiveItem]) throws {
    }
}
