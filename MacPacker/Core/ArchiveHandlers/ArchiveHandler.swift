//
//  ArchiveHandler.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 05.09.25.
//

import Foundation

class ArchiveHandler {
    public static func getTempDirectory(id: String) -> URL {
        let applicationSupport = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let appSupportSubDirectory = applicationSupport
            .appendingPathComponent("ta", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
        return appSupportSubDirectory
    }
    
    func nextPathComponent(after archivePath: String, in containerPath: String, isDirectoryHint: Bool) -> (name: String, isDirectory: Bool)? {
        // Ensure that the containerPath starts with the archivePath
        guard containerPath.hasPrefix(archivePath) else {
            return nil
        }
        
        // Get the remaining path components after archivePath
        let remainingPath = containerPath.dropFirst(archivePath.count)
        
        // Split the remaining path components by "/"
        let pathComponents = remainingPath.split(separator: "/")
        
        // The next path component is the first one after archivePath
        guard let nextPathComponent = pathComponents.first else {
            return nil
        }
        
        // Check if the next path component is a directory
        let isDirectory = pathComponents.count > 1 || remainingPath.hasSuffix("/") || isDirectoryHint == true
        
        if isDirectory {
            // Return the directory name
            return (String(nextPathComponent), true)
        } else {
            // Return the last path element (file name)
            return (String(pathComponents.last.map { String($0) }!), false)
        }
    }
    
    public func createTempDirectory() -> (id: String, path: URL)? {
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
    
    public func stripFileExtension ( _ filename: String ) -> String {
        var components = filename.components(separatedBy: ".")
        guard components.count > 1 else { return filename }
        components.removeLast()
        return components.joined(separator: ".")
    }
    
    func content(archiveUrl: URL, archivePath: String) throws -> [ArchiveItem] {
        return []
    }
    
    func extractToTemp(path: URL) -> URL? {
        return nil
    }
    
    func extractFileToTemp(path: URL, item: ArchiveItem) -> URL? {
        return nil
    }
    
    func extract(
        archiveUrl: URL,
        archiveItem: ArchiveItem,
        to url: URL
    ) {
        Logger.debug("Calling extract(archiveUrl:archiveItem:to:) without implementation")
    }
    
    func extract(
        archiveUrl: URL,
        to url: URL
    ) {
        Logger.debug("Calling extract(archiveURL:to:) without implementation")
    }
    
    var isEditable: Bool {
        get {
            return false
        }
    }
    
    func save(to: URL, items: [ArchiveItem]) throws {}
}
