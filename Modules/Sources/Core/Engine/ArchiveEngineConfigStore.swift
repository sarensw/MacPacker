//
//  HandlerRegistry.swift
//  Modules
//
//  Created by Stephan Arenswald on 25.11.25.
//

import AppKit
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "engine")

public extension UserDefaults {
    /// Where the engine settings live: the app group container, so the QuickLook
    /// extension — a separate process with its own sandbox container, and thus
    /// its own `.standard` — reads exactly the engines the app writes.
    ///
    /// The identifier comes from the running target's Info.plist
    /// (`MPAppGroupIdentifier`, fed by `$(APP_GROUP_ID)`), so Core carries no
    /// team ID, and unit tests — whose bundle has no such key — quietly stay on
    /// `.standard`.
    ///
    /// `nonisolated(unsafe)` because `UserDefaults` is documented as thread-safe
    /// but not marked `Sendable`.
    nonisolated(unsafe) static let macPackerShared: UserDefaults = {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "MPAppGroupIdentifier") as? String,
              !group.isEmpty,
              let shared = UserDefaults(suiteName: group) else {
            log.info("Engine settings use the local defaults (no app group)")
            return .standard
        }
        log.info("Engine settings use the app group", context: ["group": group])
        return shared
    }()
}

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
    /// Not private: the migration tests have to simulate an upgrade from a build
    /// that predates this flag, which means removing exactly this key. Spelling
    /// it out a second time over there would let a rename pass unnoticed.
    static let automaticKey = "automaticEngineSelection"

    private let catalog: ArchiveTypeCatalogProtocol
    /// Where the settings live. Injectable so tests can hand in an isolated
    /// suite instead of mutating the real user's preferences.
    private let defaults: UserDefaults
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
            defaults.set(isAutomatic, forKey: Self.automaticKey)
        }
    }

    public init(
        catalog: ArchiveTypeCatalogProtocol,
        defaults: UserDefaults = .standard
    ) {
        self.catalog = catalog
        self.defaults = defaults
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
    
    /// Carries settings written before they moved into the app group over to it,
    /// once, so an existing user's picks survive the update.
    ///
    /// Only the app may call this. The QuickLook extension's own `.standard` is a
    /// different container holding the engine pins an older preview build wrote
    /// there, and copying those over would silently replace the user's picks.
    ///
    /// The presence of the per-format picks is what says "already migrated" —
    /// not the automatic flag, which a preview shown before the app was ever
    /// launched has written by then, and which then has to be corrected to what
    /// the user actually chose.
    public static func migrateToSharedDefaults(
        from legacy: UserDefaults = .standard,
        to shared: UserDefaults = .macPackerShared
    ) {
        guard shared !== legacy,
              shared.object(forKey: overridesKey) == nil,
              let overrides = legacy.object(forKey: overridesKey) else { return }

        shared.set(overrides, forKey: overridesKey)
        if let automatic = legacy.object(forKey: automaticKey) {
            shared.set(automatic, forKey: automaticKey)
        }
        log.notice("Migrated the engine settings into the app group")
    }

    // MARK: - Persistence

    private func save() {
        let cfg = overrides.map { PersistedEngineConfig(formatId: $0.key, engineId: $0.value) }
        do {
            let data = try JSONEncoder().encode(cfg)
            defaults.set(data, forKey: Self.overridesKey)
        } catch {
            // up to you how noisy this should be
            print("Failed to save archive engine overrides: \(error)")
        }
    }
    
    private func load() {
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
