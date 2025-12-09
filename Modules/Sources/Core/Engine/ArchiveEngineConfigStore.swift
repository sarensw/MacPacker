//
//  HandlerRegistry.swift
//  Modules
//
//  Created by Stephan Arenswald on 25.11.25.
//

import AppKit

//public struct EngineOption {
//    public let engineId: ArchiveEngineType
//    public let capabilities: ArchiveCapabilities
//}

private struct PersistedEngineConfig: Codable {
    let formatId: String
    let engineId: ArchiveEngineType
}

/// Stores *only* user-selected engines per format.
/// Options + defaults come from ArchiveTypeCatalogProtocol (JSON-backed).
public final class ArchiveEngineConfigStore {
    private let catalog: ArchiveTypeCatalogProtocol
    /// formatId -> selected engine override
    private var overrides: [String: ArchiveEngineType] = [:]

    public init(catalog: ArchiveTypeCatalogProtocol) {
        self.catalog = catalog
        load()
    }
    
    /// Engine to use right now: override if present, else catalog default.
    public func selectedEngine(for formatId: String) -> ArchiveEngineType? {
        overrides[formatId] ?? catalog.defaultEngine(for: formatId)
    }
    
    /// All available engines for this format.
    public func engineOptions(for formatId: String) -> [EngineDto] {
        catalog.engineOptions(for: formatId)
    }
    
    /// Set a new selected engine for this format.
    /// Only accepts engines that the catalog lists as valid options.
    public func setSelectedEngine(_ engine: ArchiveEngineType, for formatId: String) {
        let options = catalog.engineOptions(for: formatId)
        guard options.contains(where: { $0.id == engine.configId }) else { return }
        overrides[formatId] = engine
        save()
    }
    
    // MARK: - Persistence
    
    private func save() {
        let cfg = overrides.map { PersistedEngineConfig(formatId: $0.key, engineId: $0.value) }
        do {
            let data = try JSONEncoder().encode(cfg)
            UserDefaults.standard.set(data, forKey: "archiveEngineConfigs")
        } catch {
            // up to you how noisy this should be
            print("Failed to save archive engine overrides: \(error)")
        }
    }
    
    private func load() {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: "archiveEngineConfigs") else { return }
        guard let decoded = try? JSONDecoder().decode([PersistedEngineConfig].self, from: data) else { return }
        
        var result: [String: ArchiveEngineType] = [:]
        
        for entry in decoded {
            // Optional: validate against current catalog options
            let validEngines = catalog.engineOptions(for: entry.formatId).map(\.id)
            if validEngines.contains(entry.engineId.configId) {
                result[entry.formatId] = entry.engineId
            }
        }
        
        overrides = result
    }
}
