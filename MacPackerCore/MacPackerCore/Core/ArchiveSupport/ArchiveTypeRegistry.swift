//
//  ArchiveTypeRegistry.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 01.11.25.
//

import Foundation

public class ArchiveTypeRegistry {
    public static let shared: ArchiveTypeRegistry = .init()
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
    
    public func handler(for detectionResult: DetectionResult) -> ArchiveHandler? {
        return handler(for: detectionResult.type.id)
    }
    
    public func handler(for url: URL) -> ArchiveHandler? {
        guard let result = detector.detect(for: url, considerComposition: false) else { return nil }
        return handler(for: result.type.id)
    }
    
    public func handler(for id: ArchiveTypeId) -> ArchiveHandler? {
        for key in archiveHandlers.keys {
            if key == id {
                return archiveHandlers[key]
            }
        }
        return nil
    }
    
    public func isSupported(url: URL) -> Bool {
        return handler(for: url) != nil
    }
    
    public func isSupported(ext: String) -> Bool {
        guard let result = detector.detectBy(ext: ext) else { return false }
        return true
    }
}
