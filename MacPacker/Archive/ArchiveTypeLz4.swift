//
//  ArchiveLz4.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 08.08.23.
//

import Foundation
import SWCompression
import System

class ArchiveTypeLz4: IArchiveType {
    var ext: String = "lz4"
    
    /// Returns the content of the lz4 file. Note that an lz4 file is just a compression algorithm.
    /// It will not contain files or folders. Therefore, this method will just return the name without
    /// the lz4 extension.
    /// - Parameters:
    ///   - path: Path to the lz4 file
    ///   - archivePath: Path within the archive. This is ignored for lz4 (is always "/")
    /// - Returns: The items to show in the UI
    public func content(path: URL, archivePath: String) throws -> [ArchiveItem] {
        if path.lastPathComponent.hasSuffix(ext) {
            let name = stripFileExtension(path.lastPathComponent)
            return [
                ArchiveItem(name: String(name), type: .file)
            ]
        }
        throw ArchiveError.invalidArchive("The given archive does not seem to be an lz4 archive in contrast to what is expected")
    }
    
    func extractFileToTemp(path: URL, item: ArchiveItem) -> URL? {
        return extractToTemp(path: path)
    }
    
    /// Extracts this archive to a temporary location in the sandbox
    /// - Returns: the directory as a file item to further process this
    func extractToTemp(path: URL) -> URL? {
        if let tempUrl = createTempDirectory() {
            
            let sourceFileName = path.lastPathComponent
            let extractedFileName = stripFileExtension(sourceFileName)
            let extractedFilePathName = tempUrl.path.appendingPathComponent(extractedFileName, isDirectory: false)
            
            print("--- Extracting...")
            print("source: \(sourceFileName)")
            print("target: \(extractedFileName)")
            print("target path: \(extractedFilePathName.path)")
            
            do {
                if let data = try? Data(contentsOf: path, options: .mappedIfSafe) {
                    print("data loaded")
                    let decompressedData = try LZ4.decompress(data: data)
                    
                    FileManager.default.createFile(atPath: extractedFilePathName.path, contents: decompressedData)
                    print("file written... in theory")
//                    return FileItem(path: extractedFilePathName, type: .archive)
                    return extractedFilePathName
                } else {
                    print("could not load")
                }
            } catch {
                print("ran in error")
                print(error)
            }
            
            print("---")
        }
        
        return nil
    }
    
    func save(to: URL, items: [ArchiveItem]) throws {
        
    }
}
