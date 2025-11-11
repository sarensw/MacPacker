//
//  Archive.swift
//  MacPackerCore
//
//  Created by Stephan Arenswald on 06.11.25.
//

import AppKit
import Combine
import Foundation

public class Archive: ObservableObject, Equatable {
    @Published public private(set) var url: URL
    public private(set) var handler: ArchiveHandler
    public private(set) var hierarchy: ArchiveHierarchy?
    public private(set) var type: ArchiveType
    
    /// Archive itself
    @Published public private(set) var name: String
    @Published public private(set) var ext: String?
    
    /// In case of the table view, this is the item for which we currently see
    /// its content. This can either be an archive, root or folder
    @Published public var selectedItem: ArchiveItem?
    @Published public private(set) var entries: [ArchiveItem] = []
    
    var rootNode: ArchiveItem = .root
    
    public init(
        url: URL,
        handler: ArchiveHandler,
        type: ArchiveType
    ) {
        self.url = url
        self.type = type
        self.handler = handler
        self.name = url.lastPathComponent
        self.rootNode.set(name: name)
        
        do {
            let entries = try handler.contents(of: url)
            self.entries = entries
            self.hierarchy = ArchiveHierarchy()
            self.hierarchy?.buildTree(for: self.entries, at: rootNode)
            self.hierarchy?.printHierarchy(item: rootNode)
            self.selectedItem = rootNode
        } catch {
            Logger.error(error.localizedDescription)
        }
    }
    
    public func clean() throws {
        print("TODO: clean")
    }
//    
//    public func open(_ item: ArchiveItem) {
//        switch item.type {
//        case .file:
//            
//            // If it is a file, check first if it has children > this can
//            // only happen if the file is an archive and if the archive
//            // was temporarily extracted before
//            if item.children != nil {
//                // Do nothing here. It is an archive. It is extracted already.
//                // We have updated the hierarchy already. Just select the item
//                selectedItem = item
//            }
//            
//            // If the children is nil, then we need to figure out if this
//            // is an archive that we actually support, or whether it is
//            // a regular file.
//            //
//            // 1. Regular File: Open the file using the system default editor
//            // 2. Archive File: Extract the archive to a temporary internal
//            //                  location, and extend the hiearchy accordingly.
//            //                  Then set the item.
//            if item.children == nil {
//                // walk up the hierarchy of the item to check if there is any
//                // handler responsible for it because the item is in a nested
//                // archive, otherwise, use the main archives handler to extract the item
//                
//                if let url = service.extract(archiveItem: item) {
//                    
//                }
//                
//                var tempItem: ArchiveItem? = item
//                var url: URL?
//                var handler: ArchiveHandler?
//                while tempItem != nil {
//                    if tempItem?.handler != nil && tempItem?.url != nil {
//                        handler = tempItem?.handler
//                        url = tempItem?.url
//                        break
//                    }
//                    tempItem = tempItem?.parent
//                }
//                if handler == nil {
//                    handler = self.handler
//                    url = self.url
//                }
//                
//                guard let handler, let url else { return }
//                
//                if let tempUrl = handler.extractFileToTemp(path: url, item: item) {
//                    
//                    let detector = ArchiveTypeDetector()
//                    
//                    if let detectionResult = detector.detectByExtension(for: tempUrl) {
//                        if let handler = ArchiveTypeRegistry.shared.handler(for: tempUrl) {
//                            // set the services required for this nested archive
//                            item.set(
//                                url: tempUrl,
//                                handler: handler,
//                                type: detectionResult.type
//                            )
//                            
//                            // nested archive is extracted > time to parse its hierarchy
//                            hierarchy?.unfold(item)
//                            hierarchy?.printHierarchy(item: rootNode)
//                            
//                            // set the nested archive as item
//                            selectedItem = item
//                        }
//                    } else {
//                        // Could not detect any archive, just open the file
//                        NSWorkspace.shared.open(tempUrl)
//                    }
//                }
//            }
//            break
//        case .archive:
//            break
//        case .root:
//            // cannot happen as this never shows up
//            break
//        case .directory:
//            selectedItem = item
//            break
//        case .unknown:
//            Logger.error("Unhandled ArchiveItem.Type: \(item.name)")
//            break
//        }
//    }
    
    public func openParent() {
        guard let parent = selectedItem?.parent else { return }
        
        if parent.type == .root {
            selectedItem = rootNode
            return
        }
        
        selectedItem = parent
    }
    
    public static func == (lhs: Archive, rhs: Archive) -> Bool {
        lhs.url == rhs.url
    }
}
