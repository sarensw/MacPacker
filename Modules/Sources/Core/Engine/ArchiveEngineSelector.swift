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

extension ArchiveEngineType {
    public init?(configId: String) {
        switch configId.lowercased() {
        case "xad":  self = .xad
        case "7zip": self = .`7zip`
        case "swc":  self = .swc
        default:     return nil
        }
    }

    /// For writing back OR for documentation
    var configId: String {
        switch self {
        case .xad:  "xad"
        case .`7zip`: "7zip"
        case .swc:  "swc"
        }
    }
}

struct ArchiveEngineSelector {
    private let archiveEngineConfigStore: ArchiveEngineConfigStore
    private var engines: [ArchiveEngineType: ArchiveEngine]
    
    init(catalog: ArchiveTypeCatalog) {
        archiveEngineConfigStore = ArchiveEngineConfigStore(catalog: catalog)
        engines = [:]
        engines[.xad] = ArchiveXadEngine()
        engines[.`7zip`] = Archive7ZipEngine()
    }
    
    func engine(for id: String) -> ArchiveEngine? {
        if let engineId = archiveEngineConfigStore.selectedEngine(for: id) {
            return engines[engineId]
        }
        
        return nil
    }
}
