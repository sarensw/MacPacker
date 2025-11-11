//
//  ArchiveItem.swift
//  MacPackerCore
//
//  Created by Stephan Arenswald on 06.11.25.
//

import Foundation

public enum ArchiveItemType: Comparable, Codable {
    case file
    case directory
    case root
    case archive
    case unknown
}

public class ArchiveItem: Identifiable, Hashable {
    public static var root: ArchiveItem {
        ArchiveItem(name: "<root>", virtualPath: "/", type: .root)
    }
    
    public let index: Int?
    public var name: String // "file1"
    public let virtualPath: String? // "folder/file1"
    public let type: ArchiveItemType
    public var ext: String
    
    // properties
    public let compressedSize: Int
    public let uncompressedSize: Int
    public let modificationDate: Date?
    public let posixPermissions: Int?
    
    // hierarchy
    public var parent: ArchiveItem?
    /// `children` is null iin case the item is a file. If the item is an archive, then
    /// it is null unless it was unfolded and added to the hierarchy already. This way
    /// we can easily distinguish if a nested archive still needs to be extracted or not.
    public private(set) var children: [ArchiveItem]? = nil
    
    // The following are only relevant if this is a nested archive
    // that can be opened
    public private(set) var url: URL?
    public private(set) var handler: ArchiveHandler?
    public private(set) var archiveType: ArchiveType?
    
    public init(
        index: Int? = nil,
        name: String,
        virtualPath: String? = nil,
        type: ArchiveItemType,
        parent: ArchiveItem? = nil,
        compressedSize: Int? = nil,
        uncompressedSize: Int? = nil,
        modificationDate: Date? = nil,
        posixPermissions: Int? = nil
    ) {
        self.name = name
        self.type = type
        self.parent = parent
        self.virtualPath = virtualPath
        self.compressedSize = compressedSize ?? -1
        self.uncompressedSize = uncompressedSize ?? -1
        self.modificationDate = modificationDate
        self.posixPermissions = posixPermissions
        self.index = index
        self.ext = ""
        
        if type != .directory {
            self.ext = getExtension(name: name)
        }
        if type == .directory {
            self.children = []
        }
    }
    
    private func getExtension(name: String) -> String {
        guard let lastDotIndex = name.lastIndex(of: ".") else {
            return ""
        }
        
        if lastDotIndex == name.startIndex {
            return ""
        }
        
        let extensionStartIndex = name.index(after: lastDotIndex)
        return String(name[extensionStartIndex...])
    }
    
    func addChild(_ child: ArchiveItem) {
        if children == nil {
            children = []
        }
        children!.append(child)
    }
    
    public static func == (lhs: ArchiveItem, rhs: ArchiveItem) -> Bool {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public func set(
        url: URL,
        handler: ArchiveHandler,
        type: ArchiveType
    ) {
        self.url = url
        self.handler = handler
        self.archiveType = type
    }
    
    public func set(
        name: String
    ) {
        self.name = name
    }
}
