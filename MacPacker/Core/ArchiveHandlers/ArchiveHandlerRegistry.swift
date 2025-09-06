//
//  ArchiveHandlerRegistry.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 04.09.25.
//

class ArchiveHandlerRegistry {
    static let shared: ArchiveHandlerRegistry = .init()
    var archiveHandlers: [String: ArchiveHandler] = [:]
    
    private init() {}
    
    func register(
        ext: String,
        handler: ArchiveHandler
    ) {
        archiveHandlers[ext] = handler
    }
    
    func handler(for ext: String) -> ArchiveHandler? {
        return archiveHandlers[ext]
    }
    
    func isSupported(ext: String) -> Bool {
        return handler(for: ext) != nil
    }
}
