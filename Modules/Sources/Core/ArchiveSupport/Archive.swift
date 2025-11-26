//
//  Archive.swift
//  MacPackerCore
//
//  Created by Stephan Arenswald on 06.11.25.
//

//import AppKit
//import Combine
//import Foundation
//
//public class Archive: ObservableObject, Equatable {
//    @Published public private(set) var url: URL
//    @Published public private(set) var type: ArchiveType
//    
//    /// Archive itself
//    @Published public private(set) var name: String
//    @Published public private(set) var ext: String?
//    
//    /// In case of the table view, this is the item for which we currently see
//    /// its content. This can either be an archive, root or folder
//    @Published public private(set) var entries: [ArchiveItem] = []
//    
//    var rootNode: ArchiveItem = .init(name: "<root>", virtualPath: "/", type: .root)
//    
//    public init(snapshot: ArchiveSnapshot) {
//        self.url = snapshot.url
//        self.type = snapshot.type
//        self.entries = snapshot.entries
//        self.name = snapshot.name
//        self.ext = snapshot.ext
//    }
//    
////    public init(
////        name: String,
////        url: URL,
////        handler: ArchiveHandler,
////        type: ArchiveType
////    ) {
////        self.url = url
////        self.type = type
////        self.handler = handler
////        self.name = name
////        self.rootNode.set(name: name)
////    }
////    
////    public func load() async throws {
////        let entries = try await handler.contents(of: url)
////        self.entries = entries
////        
////        self.hierarchy = ArchiveHierarchy()
////        self.hierarchy?.buildTree(for: self.entries, at: rootNode)
////        
////        self.selectedItem = rootNode
////    }
////    
////    public func clean() throws {
////        print("TODO: clean")
////    }
////    
//    public static func == (lhs: Archive, rhs: Archive) -> Bool {
//        lhs.url == rhs.url
//    }
//}
