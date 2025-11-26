//
//  ArchiveHierarchyPrinter.swift
//  Modules
//
//  Created by Stephan Arenswald on 23.11.25.
//

class ArchiveHierarchyPrinter {
    
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
}
