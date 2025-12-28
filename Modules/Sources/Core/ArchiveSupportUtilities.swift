//
//  ArchiveSupportUtilities.swift
//  Modules
//
//  Created by Stephan Arenswald on 24.12.25.
//

import Foundation
import System

final class ArchiveSupportUtilities {
    func createTempDirectory() -> (id: String, url: URL)? {
        do {
            let applicationSupport = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            let id = UUID().uuidString
            let appSupportSubDirectory = applicationSupport
                .appendingPathComponent("ta", isDirectory: true)
                .appendingPathComponent(id, isDirectory: true)
            try FileManager.default.createDirectory(at: appSupportSubDirectory, withIntermediateDirectories: true, attributes: nil)
            print(appSupportSubDirectory.path) // /Users/.../Library/Application Support/YourBundleIdentifier
            return (id, appSupportSubDirectory)
        } catch {
            print(error)
        }
        return nil
    }
    
    func makeTempFileDescriptor() throws -> FileDescriptor {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        FileManager.default.createFile(atPath: url.path, contents: nil)

        return try FileDescriptor.open(
            FilePath(url.path),
            .readWrite,
            options: [.truncate]
        )
    }
    
    func findHandlerAndUrl(for archiveItem: ArchiveItem) -> (String, URL)? {
        var item: ArchiveItem? = archiveItem
        var url: URL?
        var typeId: String?
    
        while item != nil {
            if item?.archiveTypeId != nil && item?.url != nil {
                url = item?.url
                typeId = item?.archiveTypeId
                break
            }
            item = item?.parent
        }
        
        guard let url, let typeId else { return nil }
    
        return (typeId, url)
    }
}
