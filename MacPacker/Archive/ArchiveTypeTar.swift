//
//  ArchiveTar.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 22.08.23.
//

import Foundation
import SWCompression

class ArchiveTypeTar: IArchiveType {
    var ext: String = "tar"
    
    /// Returns the content of the tar file in form of FileItems. There is no need to extract the tar
    /// file because it allows us to peek into the tar file and get the content.
    /// - Parameters:
    ///   - path: Path to the tar file
    ///   - archivePath: Path within the tar archive to return
    /// - Returns: Items in the archive with the given path
    public func content(archiveUrl: URL, archivePath: String) throws -> [ArchiveItem] {
        var result: [ArchiveItem] = []
        var dirs: [String] = []
        
        do {
            if let data = try? Data(contentsOf: archiveUrl, options: .mappedIfSafe) {
                print("data loaded")
                
                let entries = try TarContainer.open(container: data)
                entries.forEach { tarEntry in
                    if let npc = nextPathComponent(
                        after: archivePath,
                        in: tarEntry.info.name,
                        isDirectoryHint: tarEntry.info.type == .directory
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
                                    data: tarEntry.data))
                            }
                        } else {
                            if let name = npc.name.components(separatedBy: "/").last {
                                result.append(ArchiveItem(
                                    name: name,
                                    type: .file,
                                    virtualPath: tarEntry.info.name,
                                    data: tarEntry.data))
                            }
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
