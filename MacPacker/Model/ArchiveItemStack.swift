//
//  FileItemStack.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 08.08.23.
//

import Foundation

struct ArchiveItemStack: Sequence {
    private var stack: [ArchiveItemStackEntry] = []
    
    func peek() -> ArchiveItemStackEntry? {
        guard let topElement = stack.first else { return nil }
        return topElement
    }
    
    @discardableResult
    mutating func pop() -> ArchiveItemStackEntry? {
        if stack.count == 0 {
            return nil
        }
        return stack.removeFirst()
    }
  
    mutating func push(_ element: ArchiveItemStackEntry) {
        stack.insert(element, at: 0)
    }
    
    mutating func clear() {
        stack = []
    }
    
    func names() -> [String] {
        var names = stack.map { $0.name }
        names.reverse()
        return names
    }
    
    func last() -> ArchiveItemStackEntry? {
        return stack.last
    }
    
    func makeIterator() -> IndexingIterator<Array<ArchiveItemStackEntry>> {
        return stack.reversed().makeIterator()
    }
}

extension ArchiveItemStack: CustomStringConvertible {
    var description: String {
        let topDivider = "---ArchiveItemStack---\n"
        let bottomDivider = "-----------\n"

        var stackElements: String = ""
        for item in stack {
            stackElements = stackElements + item.description + "\n"
        }

        return topDivider + stackElements + bottomDivider
    }
    
    var count: Int {
        get {
            return stack.count
        }
    }
}
