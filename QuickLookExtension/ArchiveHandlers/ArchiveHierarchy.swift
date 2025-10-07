//
//  ArchiveHierarchy.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 03.10.25.
//

import Foundation

class ArchiveHierarchy {
    var root: ArchiveItem = .root
    
    init(entries: [XadArchiveEntry]) {
        for entry in entries {
            var node: ArchiveItem = root
            
            let components = entry.path.split(separator: "/")
            
            for i in 0..<components.count - 1 {
                let component = components[i]
                
                if let n = node.children.first(where: { $0.name == String(component) }) {
                    node = n
                } else {
                    let n = ArchiveItem(name: String(component), type: .directory)
                    node.children.append(n)
                    node = n
                }
            }
            
            node.children.append(
                ArchiveItem(
                    name: entry.name,
                    type: entry.type,
                    compressedSize: entry.compressedSize,
                    uncompressedSize: entry.uncompressedSize,
                    modificationDate: entry.modificationDate,
                    posixPermissions: entry.posixPermissions,
                    index: entry.index
                )
            )
        }
    }
}
