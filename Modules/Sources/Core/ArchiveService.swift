//
//  ArchiveService.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 08.09.25.
//

import Foundation

public class ArchiveService {
    //
    // MARK: Archive extract operations
    //
    
    /// This is the archive that this service belongs to
    private weak var archive: Archive?
    
    init(archive: Archive) {
        self.archive = archive
    }
    
    /// Extracts a number of items from the given archive to a given destination
    /// - Parameters:
    ///   - archive: archive to extract the items from
    ///   - items: items to extract (files or folders)
    ///   - destination: target destination choosen by the user
    func extract(
        archive: Archive,
        items: [ArchiveItem],
        to destination: URL
    ) {
//        guard let stackItem = archive.selectedItem else {
//            Logger.debug("No stack available")
//            return
//        }
//        
//        let _ = destination.startAccessingSecurityScopedResource()
//        defer { destination.stopAccessingSecurityScopedResource()}
//        
//        for item in items {
//            // Extract to a temporary place first for sandboxing
//            // reasons, then move from there to the target destination.
//            // The move is instant as macOS will just updates the
//            // filesystem metadata (directory entry / inode pointers)
//            guard let tempUrl = archive.handler.extractFileToTemp(
//                path: archive.url,
//                item: item) else {
//                Logger.debug("Failed to extract item to temp file")
//                return
//            }
//            
//            do {
//                try FileManager.default.moveItem(
//                    at: tempUrl,
//                    to: destination.appending(component: item.name))
//            } catch {
//                Logger.debug("Failed to move item: \(error.localizedDescription)")
//            }
//        }
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
        archive: Archive,
        to destination: URL
    ) {
//        let _ = destination.startAccessingSecurityScopedResource()
//        defer { destination.stopAccessingSecurityScopedResource()}
//        
//        archive.handler.extract(
//            archiveUrl: archive.url,
//            to: destination)
    }
}
