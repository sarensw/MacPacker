//
//  Archive.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 03.08.23.
//

import Foundation

public enum ArchiveItemType2: Comparable, Codable {
    case file
    case directory
    case archive
    case parent
    case unknown
}

public struct ArchiveItem2: Identifiable, Hashable, Codable {
    nonisolated(unsafe) public static let parent: ArchiveItem2 = ArchiveItem2(name: "..", type: .parent)
    public var id = UUID()
    public var path: URL? = nil
    public var virtualPath: String? = nil
    public let type: ArchiveItemType2
    public var name: String
    public var ext: String
    public var compressedSize: Int = -1
    public var uncompressedSize: Int = -1
    public var data: Data? = nil
    public var index: Int? = nil
    public var modificationDate: Date? = nil
    public var posixPermissions: Int? = nil
    
    //
    // Initializers
    //
    
    /// Constructor used to represent a file that actually exists on the local drive
    /// - Parameters:
    ///   - path: Actual path to the file
    ///   - type: Type of item
    ///   - size: Size of the item
    ///   - name: Name of the titem. If this is nil, then the last path component from path is used
    public init(
        path: URL,
        type: ArchiveItemType2,
        compressedSize: Int? = nil,
        uncompressedSize: Int? = nil,
        name: String? = nil
    ) {
        self.path = path
        self.type = type
        self.name = name ?? path.lastPathComponent
        self.compressedSize = compressedSize ?? -1
        self.uncompressedSize = uncompressedSize ?? -1
        self.ext = ""
        
        if type != .directory {
            self.ext = getExtension(name: name ?? path.lastPathComponent)
        }
    }
    
    /// Constructor used to represent an item that virtually exist. This refers to items that
    /// are not yet extracted, so do not have a local path.
    /// - Parameters:
    ///   - name: Name of the item
    ///   - type: Type of the item
    ///   - virtualPath: The virtual path, for example in an archive
    ///   - size: Size of the item
    ///   - data: Data of the item if available
    ///   - index: Index of the item within the archive
    public init(
        name: String,
        type: ArchiveItemType2,
        virtualPath: String? = nil,
        compressedSize: Int? = nil,
        uncompressedSize: Int? = nil,
        data: Data? = nil,
        index: Int? = nil,
        modificationDate: Date? = nil,
        posixPermissions: Int? = nil
    ) {
        self.virtualPath = virtualPath
        self.name = name
        self.compressedSize = compressedSize ?? -1
        self.uncompressedSize = uncompressedSize ?? -1
        self.type = type
        self.ext = ""
        self.data = data
        self.index = index
        self.modificationDate = modificationDate
        self.posixPermissions = posixPermissions
        
        if type != .directory {
            self.ext = getExtension(name: name)
        }
//        self.name = getName(archiveName: name)
    }
    
    //
    // Functions
    //
    
    private func getName(archiveName: String) -> String {
        var name = archiveName
        
        // in tar, directories have a "/" at the end > remove this first
        if name.last == "/" {
             _ = name.popLast()
        }
        
        // search for the last "/" and then take everything after that
        if var lastSlashIndex = name.lastIndex(of: "/") {
            lastSlashIndex = name.index(after: lastSlashIndex)
            name = String(name[lastSlashIndex...])
        }
        
        return name
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
    
    // opens the item
    // - file > open using system functionality
    // - archive > open in macpacker
    // - directory > open in macpacker
    public func open(_ name: String) {
        
    }
    
    public static func == (lhs: ArchiveItem2, rhs: ArchiveItem2) -> Bool {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension ArchiveItem2: CustomStringConvertible {
    public var description: String {
        return path == nil ? "" : path!.absoluteString
    }
}
