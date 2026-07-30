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
public final class ArchiveEngineConfigStore: @unchecked Sendable {
    private static let overridesKey = "archiveEngineConfigs"
    private static let automaticKey = "automaticEngineSelection"

    private let catalog: ArchiveTypeCatalogProtocol
    /// formatId -> selected engine override
    private var overrides: [String: ArchiveEngineType] = [:]

    /// Whether MacPacker picks the engine itself.
    ///
    /// On: the catalog defaults are used and the loader may fall back to another
    /// engine when the default cannot read a particular archive. Off: the user's
    /// per-format picks are used exactly as chosen, and nothing falls back.
    ///
    /// Most people neither know nor care which engine opens their archive; the
    /// per-format picker is an advanced tool. So this defaults on — except for
    /// anyone who already made a pick, whose choices are kept (see `load`).
    public var isAutomatic: Bool {
        didSet {
            guard isAutomatic != oldValue else { return }
            UserDefaults.standard.set(isAutomatic, forKey: Self.automaticKey)
        }
    }

    public init(catalog: ArchiveTypeCatalogProtocol) {
        self.catalog = catalog
        self.isAutomatic = true
        load()
    }

    /// Engine to use right now.
    ///
    /// In automatic mode the catalog default wins, so a stored override is kept
    /// on disk but ignored — switching automatic back off restores it.
    public func selectedEngine(for formatId: String) -> ArchiveEngineType? {
        if isAutomatic {
            return catalog.defaultEngine(for: formatId)
        }
        return overrides[formatId] ?? catalog.defaultEngine(for: formatId)
    }

    /// Whether the user has ever picked an engine for any format.
    public var hasAnyOverride: Bool { !overrides.isEmpty }
    
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
            UserDefaults.standard.set(data, forKey: Self.overridesKey)
        } catch {
            // up to you how noisy this should be
            print("Failed to save archive engine overrides: \(error)")
        }
    }
    
    private func load() {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: Self.overridesKey),
           let decoded = try? JSONDecoder().decode([PersistedEngineConfig].self, from: data) {
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

        if defaults.object(forKey: Self.automaticKey) != nil {
            isAutomatic = defaults.bool(forKey: Self.automaticKey)
            return
        }

        // First launch after automatic mode shipped. Anyone who already picked
        // an engine did so deliberately, so leave them in manual mode with their
        // picks intact; everyone else gets automatic. Written straight away so
        // the decision is made once and not re-derived as overrides change.
        isAutomatic = overrides.isEmpty
        defaults.set(isAutomatic, forKey: Self.automaticKey)
    }
}
