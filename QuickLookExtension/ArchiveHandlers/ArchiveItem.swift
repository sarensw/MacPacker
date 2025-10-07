//
//  ArchiveItem.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 03.10.25.
//

import Foundation

enum ArchiveItemType {
    case file
    case directory
    case root
}

class ArchiveItem {
    public static var root: ArchiveItem {
        ArchiveItem(name: "", type: .root)
    }
    
    let name: String
    let type: ArchiveItemType
    let compressedSize: Int
    let uncompressedSize: Int
    let modificationDate: Date?
    let posixPermissions: Int?
    let index: Int32?
    var ext: String
    var children: [ArchiveItem] = []
    
    init(
        name: String,
        type: ArchiveItemType,
        compressedSize: Int? = nil,
        uncompressedSize: Int? = nil,
        modificationDate: Date? = nil,
        posixPermissions: Int? = nil,
        index: Int32? = nil
    ) {
        self.name = name
        self.type = type
        self.compressedSize = compressedSize ?? -1
        self.uncompressedSize = uncompressedSize ?? -1
        self.modificationDate = modificationDate
        self.posixPermissions = posixPermissions
        self.index = index
        self.ext = ""
        
        if type != .directory {
            self.ext = getExtension(name: name)
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
        children.append(child)
    }
}
