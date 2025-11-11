//
//  ArchiveState.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 04.05.25.
//

import Combine
import Foundation
import SwiftUI

public class ArchiveState: ObservableObject {
    @Published public var archive: Archive?
    @Published public var isReloadNeeded: Bool = false
    @Published public var selectedItems: [ArchiveItem] = []
    @Published public var openWithUrls: [URL] = []
    @Published public var completePathArray: [String] = []
    @Published public var completePath: String?
    @Published public var previewItemUrl: URL?
    
    public init() {
    }
    
    public init(completePath: String) {
        self.completePath = completePath
    }
}

extension ArchiveState {
    
    //
    // MARK: General
    //
    
    public func loadUrl(_ url: URL) {
        createArchive(url: url)
    }
    
    public func open(_ item: ArchiveItem) {
        guard let archive else { return }
        
        switch item.type {
        case .file:
            
            // If it is a file, check first if it has children > this can
            // only happen if the file is an archive and if the archive
            // was temporarily extracted before
            if item.children != nil {
                // Do nothing here. It is an archive. It is extracted already.
                // We have updated the hierarchy already. Just select the item
                archive.selectedItem = item
            }
            
            // If the children is nil, then we need to figure out if this
            // is an archive that we actually support, or whether it is
            // a regular file.
            //
            // 1. Regular File: Open the file using the system default editor
            // 2. Archive File: Extract the archive to a temporary internal
            //                  location, and extend the hiearchy accordingly.
            //                  Then set the item.
            if item.children == nil {
                // walk up the hierarchy of the item to check if there is any
                // handler responsible for it because the item is in a nested
                // archive, otherwise, use the main archives handler to extract the item
                
                if let tempUrl = extract(archiveItem: item) {
                    
                    let detector = ArchiveTypeDetector()
                    
                    // We check by extension here because we don't want to end up
                    // opening files like .xlsx as an archive. An Excel file (or any
                    // other archived file that is basically a .zip file) should be
                    // extracted and treated like an Excel file instead of an archive
                    //
                    // TODO: Add the possibility via right click menu in MacPacker
                    //       to open the file as archive instead.
                    if let detectionResult = detector.detectByExtension(for: tempUrl) {
                        if let handler = ArchiveTypeRegistry.shared.handler(for: tempUrl) {
                            // set the services required for this nested archive
                            item.set(
                                url: tempUrl,
                                handler: handler,
                                type: detectionResult.type
                            )
                            
                            // nested archive is extracted > time to parse its hierarchy
                            archive.hierarchy?.unfold(item)
                            archive.hierarchy?.printHierarchy(item: archive.rootNode)
                            
                            // set the nested archive as item
                            archive.selectedItem = item
                        }
                    } else {
                        // Could not detect any archive, just open the file
                        NSWorkspace.shared.open(tempUrl)
                    }
                }
            }
            break
        case .archive:
            break
        case .root:
            // cannot happen as this never shows up
            break
        case .directory:
            archive.selectedItem = item
            break
        case .unknown:
            Logger.error("Unhandled ArchiveItem.Type: \(item.name)")
            break
        }
    }
    
    public func openParent() {
        if archive?.selectedItem == .root {
            archive?.selectedItem = archive?.rootNode
            return
        }
        
        archive?.selectedItem = archive?.selectedItem?.parent
    }
    
    /// This will extract the given item from the archive to a temporary destination
    /// - Parameter archiveItem: item to extract
    /// - Returns: the url of the extracted file when successful
    public func extract(archiveItem: ArchiveItem) -> URL? {
        // We need to figure out first which archive actually contains
        // the currently selected file. Is it the root archive, or is
        // it a nested archive?
        
        let (handler, archiveUrl) = findHandlerAndUrl(for: archiveItem)
        if let handler, let archiveUrl {
            let url = handler.extractFileToTemp(path: archiveUrl, item: archiveItem)
            return url
        }
        
        return nil
    }
    
    private func findHandlerAndUrl(for archiveItem: ArchiveItem) -> (ArchiveHandler?, URL?) {
        var item: ArchiveItem? = archiveItem
        var url: URL?
        var handler: ArchiveHandler?
        
        while item != nil {
            if item?.handler != nil && item?.url != nil {
                url = item?.url
                handler = item?.handler
                break
            }
            item = item?.parent
        }
        
        if handler == nil || url == nil {
            handler = archive?.handler
            url = archive?.url
        }
        
        return (handler, url)
    }
    
    /// Extracts a number of items from the given archive to a given destination
    /// - Parameters:
    ///   - archive: archive to extract the items from
    ///   - items: items to extract (files or folders)
    ///   - destination: target destination choosen by the user
    public func extract(
        archive: Archive,
        items: [ArchiveItem],
        to destination: URL
    ) {
        guard let stackItem = archive.selectedItem else {
            Logger.debug("No stack available")
            return
        }
        
        let _ = destination.startAccessingSecurityScopedResource()
        defer { destination.stopAccessingSecurityScopedResource()}
        
        for item in items {
            let (handler, url) = findHandlerAndUrl(for: item)
            guard let handler, let url else {
                Logger.debug("Failed to find handler or url for item")
                return
            }
            
            // Extract to a temporary place first for sandboxing
            // reasons, then move from there to the target destination.
            // The move is instant as macOS will just updates the
            // filesystem metadata (directory entry / inode pointers)
            guard let tempUrl = handler.extractFileToTemp(
                path: url,
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
    public func extract(
        archive: Archive,
        to destination: URL
    ) {
        let _ = destination.startAccessingSecurityScopedResource()
        defer { destination.stopAccessingSecurityScopedResource()}
        
        archive.handler.extract(
            archiveUrl: archive.url,
            to: destination)
    }
    
    public func createArchive(url: URL) {
//            let archive = try Archive2(
//                url: url,
//                breadcrumbsUpdated: breadcrumbsUpdated(breadcrumbs:))
        let detector = ArchiveTypeDetector()
        if let detectorResult = detector.detect(for: url),
           let handler = ArchiveTypeRegistry.shared.handler(for: url) {
            let archive = Archive(
                url: url,
                handler: handler,
                type: detectorResult.type
            )
            self.archive = archive
        }
        self.isReloadNeeded = true
    }
    
    public func breadcrumbsUpdated(breadcrumbs: [String]) {
        self.completePathArray = breadcrumbs
        self.completePath = breadcrumbs.joined(separator: "/")
    }
    
    /// Checks if the given archive extension is supported to be loaded in MacPacker
    /// - Parameter url: url to the archive in question
    /// - Returns: true in case supported, false otherwise
    public func isSupportedArchive(url: URL) -> Bool {
        return ArchiveTypeRegistry.shared.isSupported(url: url)
    }
    
    /// Updates the quick look preview URL. The previewer we're using is the default systems
    /// preview that is called Quick Look and that can be reached via Space in Finder
    ///
    /// When Space is pressed by the user while any item is selected, we're opening this default
    /// preview to support any file type that is supported by the system anyways. This might
    /// also override any previously selected item in which case quick look will just adopt.
    ///
    /// In case no item is selected then set the preview url to nil to make sure Quick Look is closing.
    public func updateSelectedItemForQuickLook() {
        if let archive = self.archive,
           let selectedItem = self.selectedItems.first {
            let handler = archive.handler
            let url = handler.extractFileToTemp(
                path: archive.url,
                item: selectedItem
            )
            self.previewItemUrl = url
        } else if self.selectedItems.isEmpty {
            self.previewItemUrl = nil
        }
    }
}

