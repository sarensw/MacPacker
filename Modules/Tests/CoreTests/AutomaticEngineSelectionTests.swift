//
//  AutomaticEngineSelectionTests.swift
//  Modules
//
//  Created by Stephan Arenswald on 30.07.26.
//

import Testing
import Foundation
@testable import Core

/// `ArchiveEngineConfigStore` persists to `UserDefaults.standard`, so these
/// tests own that state explicitly: cleared before each case and restored after.
/// Everything else in the suite avoids UserDefaults entirely by pinning engines
/// through the test doubles — this is the one place the persistence itself is
/// what's under test.
private struct EngineDefaults {
    static let overridesKey = "archiveEngineConfigs"
    static let automaticKey = "automaticEngineSelection"

    static func clear() {
        UserDefaults.standard.removeObject(forKey: overridesKey)
        UserDefaults.standard.removeObject(forKey: automaticKey)
    }

    /// Writes overrides the way a previous MacPacker version would have, i.e.
    /// without ever having heard of the automatic flag.
    static func seedLegacyOverride(_ engine: ArchiveEngineType, for formatId: String) {
        clear()
        let store = ArchiveEngineConfigStore(catalog: ArchiveTypeCatalog())
        store.isAutomatic = false
        store.setSelectedEngine(engine, for: formatId)
        // Drop only the flag, leaving the overrides — an upgrade from a build
        // that had per-format engines but no automatic mode.
        UserDefaults.standard.removeObject(forKey: automaticKey)
    }
}

extension AllCoreTests {

    @MainActor struct AutomaticEngineSelectionTests {

        // MARK: - First launch after the feature ships

        /// Nobody has picked an engine, so MacPacker picks.
        @Test func defaultsToAutomaticForAFreshInstall() {
            EngineDefaults.clear()
            defer { EngineDefaults.clear() }

            let store = ArchiveEngineConfigStore(catalog: ArchiveTypeCatalog())
            #expect(store.isAutomatic)
            #expect(store.hasAnyOverride == false)
        }

        /// Someone who already chose XAD for rar chose it deliberately. Their
        /// setting must survive the upgrade rather than being overruled by a
        /// feature that did not exist when they set it.
        @Test func staysManualWhenTheUserAlreadyPickedAnEngine() {
            EngineDefaults.seedLegacyOverride(.xad, for: "rar")
            defer { EngineDefaults.clear() }

            let store = ArchiveEngineConfigStore(catalog: ArchiveTypeCatalog())
            #expect(store.isAutomatic == false, "an existing choice was overruled")
            #expect(store.selectedEngine(for: "rar") == .xad, "the choice itself was lost")
        }

        /// The migration decides once. Picking an engine later must not flip the
        /// mode, and neither must a restart.
        @Test func theMigrationDecisionIsMadeOnlyOnce() {
            EngineDefaults.clear()
            defer { EngineDefaults.clear() }

            let first = ArchiveEngineConfigStore(catalog: ArchiveTypeCatalog())
            #expect(first.isAutomatic)

            first.isAutomatic = false
            first.setSelectedEngine(.xad, for: "rar")

            // Restart.
            let second = ArchiveEngineConfigStore(catalog: ArchiveTypeCatalog())
            #expect(second.isAutomatic == false, "the mode did not survive a restart")
            #expect(second.selectedEngine(for: "rar") == .xad)
        }

        // MARK: - What each mode resolves to

        /// Automatic ignores overrides without destroying them, so turning the
        /// toggle back off restores exactly what the user had.
        @Test func automaticIgnoresOverridesButKeepsThem() {
            EngineDefaults.clear()
            defer { EngineDefaults.clear() }

            let catalog = ArchiveTypeCatalog()
            let store = ArchiveEngineConfigStore(catalog: catalog)
            store.isAutomatic = false
            store.setSelectedEngine(.xad, for: "rar")
            #expect(store.selectedEngine(for: "rar") == .xad)

            store.isAutomatic = true
            #expect(
                store.selectedEngine(for: "rar") == catalog.defaultEngine(for: "rar"),
                "automatic mode did not fall back to the catalog default"
            )

            store.isAutomatic = false
            #expect(store.selectedEngine(for: "rar") == .xad, "the override did not come back")
        }

        // MARK: - Which mode allows a fallback

        /// The whole point of the toggle: only automatic mode may switch engines.
        @Test func onlyAutomaticModeAllowsFallback() {
            EngineDefaults.clear()
            defer { EngineDefaults.clear() }

            let catalog = ArchiveTypeCatalog()
            let store = ArchiveEngineConfigStore(catalog: catalog)
            let selector = ArchiveEngineSelector(catalog: catalog, configStore: store)

            store.isAutomatic = true
            #expect(selector.allowsEngineFallback)

            store.isAutomatic = false
            #expect(selector.allowsEngineFallback == false)
        }

        /// The project's single-engine doubles must stay strict without opting
        /// out, so any test written against one engine really tests that engine.
        @Test func testDoublesAreStrictByDefault() {
            #expect(ArchiveEngineSelector7zip().allowsEngineFallback == false)
            #expect(ArchiveEngineSelectorXad().allowsEngineFallback == false)
            #expect(ArchiveEngineSelectorSwc().allowsEngineFallback == false)
            #expect(ArchiveEngineSelectorAutomatic(.xad).allowsEngineFallback)
        }
    }
}
