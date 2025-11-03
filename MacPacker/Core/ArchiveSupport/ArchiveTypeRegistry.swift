//
//  ArchiveTypeRegistry.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 01.11.25.
//

import Foundation

public class ArchiveTypeRegistry {
    static let shared: ArchiveTypeRegistry = .init()
    var archiveHandlers: [ArchiveTypeId: ArchiveHandler] = [:]
    
    let detector = ArchiveTypeDetector()
    
    private init() {}
    
    func register(
        typeID: ArchiveTypeId,
        capabilities: [ArchiveCapability],
        handler: ArchiveHandler
    ) {
        archiveHandlers[typeID] = handler
    }
    
    func handler(for url: URL) -> ArchiveHandler? {
        guard let result = detector.detect(for: url) else { return nil }
        return handler(for: result.type.id)
    }
    
    func handler(for id: ArchiveTypeId) -> ArchiveHandler? {
        for key in archiveHandlers.keys {
            if key == id {
                return archiveHandlers[key]
            }
        }
        return nil
    }
    
    func isSupported(url: URL) -> Bool {
        return handler(for: url) != nil
    }
    
    func isSupported(ext: String) -> Bool {
        guard let result = detector.detectBy(ext: ext) else { return false }
        return true
    }
}
