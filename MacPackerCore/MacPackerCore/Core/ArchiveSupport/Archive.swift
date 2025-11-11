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
    
    public static func == (lhs: Archive, rhs: Archive) -> Bool {
        lhs.url == rhs.url
    }
}
