//
//  ArchiveHandlerLz4.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 05.09.25.
//

import Foundation
import SWCompression

public class ArchiveHandlerLz4: ArchiveHandler {
    private static let ext = "lz4"
    
    public static func register() {
        let handler = ArchiveHandlerLz4()
        
        let typeRegistry = ArchiveTypeRegistry.shared
        
        typeRegistry.register(typeID: .lz4, capabilities: [.view, .extract], handler: handler)
        
    }
    
    /// Returns the content of the lz4 file. Note that an lz4 file is just a compression algorithm.
    /// It will not contain files or folders. Therefore, this method will just return the name without
    /// the lz4 extension.
    /// - Parameters:
    ///   - path: Path to the lz4 file
    ///   - archivePath: Path within the archive. This is ignored for lz4 (is always "/")
    /// - Returns: The items to show in the UI
    public override func content(archiveUrl: URL, archivePath: String) throws -> [ArchiveItem] {
        if archiveUrl.lastPathComponent.hasSuffix(Self.ext) {
            let name = stripFileExtension(archiveUrl.lastPathComponent)
            return [
                ArchiveItem(name: String(name), type: .file)
            ]
        }
        throw ArchiveError.invalidArchive("The given archive does not seem to be an lz4 archive in contrast to what is expected")
    }
    
    public override func extractFileToTemp(path: URL, item: ArchiveItem) -> URL? {
        return extractToTemp(path: path)
    }
    
    /// Extracts this archive to a temporary location in the sandbox
    /// - Returns: the directory as a file item to further process this
    public override func extractToTemp(path: URL) -> URL? {
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
    
    public override func extract(
        archiveUrl: URL,
        archiveItem: ArchiveItem,
        to url: URL
    ) {
        extract(archiveUrl: archiveUrl, to: url)
    }
    
    public override func extract(
        archiveUrl: URL,
        to url: URL
    ) {
        let sourceFileName = archiveUrl.lastPathComponent
        let extractedFileName = stripFileExtension(sourceFileName)
        let extractedFilePathName = url.appendingPathComponent(extractedFileName, isDirectory: false)
        
        do {
            if let data = try? Data(contentsOf: archiveUrl, options: .mappedIfSafe) {
                let decompressedData = try LZ4.decompress(data: data)
                
                FileManager.default.createFile(atPath: extractedFilePathName.path, contents: decompressedData)
            } else {
                Logger.error("Could not decompress archive")
            }
        } catch {
            Logger.error(error.localizedDescription)
        }
    }
}
