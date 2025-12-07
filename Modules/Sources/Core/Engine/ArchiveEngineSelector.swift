//
//  ArchiveEngineSelector.swift
//  Modules
//
//  Created by Stephan Arenswald on 25.11.25.
//

import Foundation

public enum ArchiveEngineType: String, Identifiable, Sendable, Codable {
    case xad = "XAD (The Unarchiver)"
    case `7zip` = "7-Zip"
    case swc = "SWCompression"
    
    public var id: Self { self }
}

struct ArchiveEngineSelector {
    private let archiveEngineConfigStore: ArchiveEngineConfigStore
    private var engines: [ArchiveEngineType: ArchiveEngine]
    
    init() {
        archiveEngineConfigStore = ArchiveEngineConfigStore()
        engines = [:]
        engines[.xad] = ArchiveXadEngine()
        engines[.`7zip`] = Archive7ZipEngine()
    }
    
    func engine(for id: ArchiveTypeId) -> ArchiveEngine? {
        if let engineId = archiveEngineConfigStore.selectedEngine(for: id) {
            return engines[engineId]
        }
        
        return nil
    }
}
