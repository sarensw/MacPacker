//
//  ArchiveHandlerRegistry.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 04.09.25.
//

import Foundation

public class ArchiveHandlerRegistry {
    static let shared: ArchiveHandlerRegistry = .init()
    var archiveHandlers: [String: ArchiveHandler] = [:]
    
    private init() {}
    
    func register(
        ext: String,
        handler: ArchiveHandler
    ) {
        archiveHandlers[ext] = handler
    }
    
    func handler(for url: URL) -> ArchiveHandler? {
        return handler(for: url.pathExtension)
    }
    
    func handler(for ext: String) -> ArchiveHandler? {
        for key in archiveHandlers.keys {
            if key.lowercased() == ext.lowercased() {
                return archiveHandlers[key]
            }
        }
        return nil
    }
    
    func isSupported(ext: String) -> Bool {
        return handler(for: ext) != nil
    }
}
