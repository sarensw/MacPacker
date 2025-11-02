//
//  ArchiveService.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 08.09.25.
//

import Foundation

class ArchiveService {
    //
    // MARK: Archive extract operations
    //
    
    /// Extracts a number of items from the given archive to a given destination
    /// - Parameters:
    ///   - archive: archive to extract the items from
    ///   - items: items to extract (files or folders)
    ///   - destination: target destination choosen by the user
    func extract(
        archive: Archive2,
        items: [ArchiveItem],
        to destination: URL
    ) {
        guard let stackItem = archive.stack.peek() else {
            Logger.debug("No stack available")
            return
        }
        guard let archivePath = stackItem.archivePath else {
            Logger.debug("Archive seems to be a new one, no type/ext set yet")
            // TODO: In this case, the file has a physical on the device and should be opened there
            return
        }
        let url = URL(fileURLWithPath: archivePath)
        guard let handler = ArchiveTypeRegistry.shared.handler(for: url) else {
            Logger.debug("No handler registered for \(String(describing: archive.ext))")
            return
        }
        
        let _ = destination.startAccessingSecurityScopedResource()
        defer { destination.stopAccessingSecurityScopedResource()}
        
        for item in items {
            // Extract to a temporary place first for sandboxing
            // reasons, then move from there to the target destination.
            // The move is instant as macOS will just updates the
            // filesystem metadata (directory entry / inode pointers)
            guard let tempUrl = handler.extractFileToTemp(
                path: stackItem.localPath,
                item: item) else {
                Logger.debug("Failed to extract item to temp file")
                return
            }
            
            do {
                try FileManager.default.moveItem(
                    at: tempUrl,
                    to: destination.appending(component: item.name))
            } catch {
                Logger.debug("Failed to move item: \(error.localizedDescription)")
            }
        }
    }
    
    /// Extracts the full archive to the given destination, preserving the folder structure.
    /// Right now, embedded archives are not extracted.
    ///
    /// TODO: Might be worth a toggle to do this?
    ///
    /// - Parameters:
    ///   - archive: the archive to extract
    ///   - destination: the destination where to extract the archive to
    func extract(
        archive: Archive2,
        to destination: URL
    ) {
        guard let url = archive.url else {
            Logger.debug("URL not a valid URL")
            return
        }
        guard let handler = ArchiveTypeRegistry.shared.handler(for: url) else {
            Logger.debug("No handler registered for \(String(describing: archive.ext))")
            return
        }
        
        let _ = destination.startAccessingSecurityScopedResource()
        defer { destination.stopAccessingSecurityScopedResource()}
        
        handler.extract(
            archiveUrl: url,
            to: destination)
    }
}
