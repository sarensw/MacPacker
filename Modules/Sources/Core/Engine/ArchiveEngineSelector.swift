//
//  ArchiveEngineSelector.swift
//  Modules
//
//  Created by Stephan Arenswald on 25.11.25.
//

import Foundation

public enum ArchiveEngineType: String, Sendable {
    case xad
    case `7zip`
    case swc
}

public struct ArchiveEngineSelector {
    private let handlerRegistry: HandlerRegistry
    private var engines: [ArchiveEngineType: ArchiveEngine]
    
    init() {
        handlerRegistry = HandlerRegistry()
        engines = [:]
        engines[.xad] = ArchiveXadEngine()
        engines[.`7zip`] = Archive7ZipEngine()
    }
    
    public func engine(for id: ArchiveTypeId) -> ArchiveEngine? {
        if let binding = handlerRegistry.handler(for: id) {
            let engineId = binding.archiveEngineId
            return engines[engineId]
        }
        
        return nil
    }
}
