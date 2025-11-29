//
//  SandBoxedGroupBookmarksImporter.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 22.09.25.
//

import Core
import Foundation

class SandboxedGroupBookmarks {
    private static let groupID = "group.app.macpacker"
    private let containerUrl = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: SandboxedGroupBookmarks.groupID)!
        .appending(path: "urlshare", directoryHint: .isDirectory)

    init() {
        do {
            try FileManager.default.createDirectory(at: containerUrl, withIntermediateDirectories: true)
            Logger.log("Created container directory at \(containerUrl)")
        } catch {
            Logger.error("Error creating container directory: \(error)")
        }
    }

    func readShareableBookmarks(_ ids: [String]) -> [URL] {
        var result: [URL] = []
        
        for id in ids {
            let path = containerUrl.appending(path: "\(id).bmk")
            guard let data = try? Data(contentsOf: path) else { continue }
            
            var stale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                )
                
                result.append(url)
            } catch {
                Logger.error("Failed to read bookmark for \(id): \(error)")
                return []
            }
        }
        
        return result
    }
    
    func createShareableBookmark(for url: URL) throws -> (uuid: String, path: URL) {
        Logger.log("Attempting to create book mark for \(url)")
        Logger.log(String(url.startAccessingSecurityScopedResource()))
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        Logger.log("Data received of length \(data.count)")
        
        let id = UUID().uuidString
        Logger.log("Generated UUID \(id)")
        
        let bookmarkPath = containerUrl.appending(path: "\(id).bmk")
        Logger.log("Created bookmark at \(bookmarkPath) with data length \(data.count) and id \(id)")
        
        try data.write(to: bookmarkPath, options: .atomic)
        Logger.log("Wrote bookmark data to file.")
        
        return (id, bookmarkPath)
    }
}
