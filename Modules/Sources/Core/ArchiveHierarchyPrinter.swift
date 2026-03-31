//
//  ArchiveHierarchyPrinter.swift
//  Modules
//
//  Created by Stephan Arenswald on 23.11.25.
//

import Foundation

class ArchiveHierarchyPrinter {
    
    public func printHierarchy(entries: [UUID: ArchiveItem], id: UUID, level: Int = 0) {
        guard let entry = entries[id] else {
            return
        }
        
        if level == 0 {
            print(entry.name)
        } else {
            print(String(repeating: " ", count: level * 2) + entry.name)
        }
        if let children = entry.children {
            for child in children {
                printHierarchy(entries: entries, id: child, level: level + 1)
            }
        }
    }
}
