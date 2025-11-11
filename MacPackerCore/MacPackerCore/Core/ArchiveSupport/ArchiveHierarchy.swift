//
//  ArchiveHiearchy.swift
//  MacPackerCore
//
//  Created by Stephan Arenswald on 06.11.25.
//

import Foundation

public class ArchiveHierarchy {
    public func buildTree(for entries: [ArchiveItem], at root: ArchiveItem) {
        for entry in entries {
            guard let virtualPath = entry.virtualPath else { continue }
            var parent: ArchiveItem = root
            
            let components = virtualPath.split(separator: "/")
            
            for i in 0..<components.count - 1 {
                let component = components[i]
                
                if let n = parent.children?.first(where: { $0.name == String(component) }) {
                    parent = n
                } else {
                    let n = ArchiveItem(
                        name: String(component),
                        virtualPath: virtualPath,
                        type: .directory,
                        parent: parent
                    )
                    parent.addChild(n)
                    parent = n
                }
            }
            
            entry.parent = parent
            parent.addChild(entry)
        }
    }
    
    public func printHierarchy(item: ArchiveItem, level: Int = 0) {
        if level == 0 {
            print(item.name)
        } else {
            print(String(repeating: " ", count: level * 2) + item.name)
        }
        if let children = item.children {
            for child in children {
                printHierarchy(item: child, level: level + 1)
            }
        }
    }
    
    public func printEntries(entries: [ArchiveItem]) {
        for entry in entries {
            if let children = entry.children, !children.isEmpty {
                print("\(entry.name): \(entry.parent!.name): \(children.count)")
            } else {
                print("\(entry.name): \(entry.parent!.name)")
            }
        }
    }
    
    public func unfold(_ archiveItem: ArchiveItem) {
        if let url = archiveItem.url,
           let handler = archiveItem.handler,
           let entries = try? handler.contents(of: url) {
            buildTree(for: entries, at: archiveItem)
        }
    }
}
