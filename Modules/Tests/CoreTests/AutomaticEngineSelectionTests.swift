//
//  AutomaticEngineSelectionTests.swift
//  Modules
//
//  Created by Stephan Arenswald on 30.07.26.
//

import Testing
import Foundation
@testable import Core

extension AllCoreTests {

    /// Every case here injects its own empty defaults suite. Nothing reads or
    /// writes `UserDefaults.standard`, so these tests neither depend on the
    /// machine's settings nor disturb them, and cannot leak into each other.
    @MainActor struct AutomaticEngineSelectionTests {

        /// A store as it would be on the very first launch of a build that has
        /// automatic mode, for a user who already picked engines in an older one.
        private func storeUpgradingFrom(
            overrides: [String: ArchiveEngineType],
            defaults: UserDefaults
        ) -> ArchiveEngineConfigStore {
            let catalog = ArchiveTypeCatalog()
            let seed = ArchiveEngineConfigStore(catalog: catalog, defaults: defaults)
            seed.isAutomatic = false
            for (formatId, engine) in overrides {
                seed.setSelectedEngine(engine, for: formatId)
            }
            // Drop only the flag: an upgrade from a build that had per-format
            // engines but had never heard of automatic mode.
            defaults.removeObject(forKey: ArchiveEngineConfigStore.automaticKey)

            return ArchiveEngineConfigStore(catalog: catalog, defaults: defaults)
        }

        // MARK: - First launch after the feature ships

        /// Nobody has picked an engine, so MacPacker picks.
        @Test func defaultsToAutomaticForAFreshInstall() {
            let store = ArchiveEngineConfigStore(
                catalog: ArchiveTypeCatalog(),
                defaults: isolatedDefaults()
            )
            #expect(store.isAutomatic)
            #expect(store.hasAnyOverride == false)
        }

        /// Someone who already chose XAD for rar chose it deliberately. That must
        /// survive the upgrade rather than being overruled by a feature that did
        /// not exist when they set it.
        @Test func staysManualWhenTheUserAlreadyPickedAnEngine() {
            let store = storeUpgradingFrom(
                overrides: ["rar": .xad],
                defaults: isolatedDefaults()
            )
            #expect(store.isAutomatic == false, "an existing choice was overruled")
            #expect(store.selectedEngine(for: "rar") == .xad, "the choice itself was lost")
        }

        /// The migration decides once. Picking an engine later must not flip the
        /// mode, and neither must a restart.
        @Test func theMigrationDecisionIsMadeOnlyOnce() {
            let defaults = isolatedDefaults()
            let catalog = ArchiveTypeCatalog()

            let first = ArchiveEngineConfigStore(catalog: catalog, defaults: defaults)
            #expect(first.isAutomatic)

            first.isAutomatic = false
            first.setSelectedEngine(.xad, for: "rar")

            let afterRestart = ArchiveEngineConfigStore(catalog: catalog, defaults: defaults)
            #expect(afterRestart.isAutomatic == false, "the mode did not survive a restart")
            #expect(afterRestart.selectedEngine(for: "rar") == .xad)
        }

        // MARK: - What each mode resolves to

        /// Automatic ignores overrides without destroying them, so turning the
        /// toggle back off restores exactly what the user had.
        @Test func automaticIgnoresOverridesButKeepsThem() {
            let catalog = ArchiveTypeCatalog()
            let store = ArchiveEngineConfigStore(catalog: catalog, defaults: isolatedDefaults())
            store.isAutomatic = false
            store.setSelectedEngine(.xad, for: "rar")
            #expect(store.selectedEngine(for: "rar") == .xad)

            store.isAutomatic = true
            #expect(
                store.selectedEngine(for: "rar") == catalog.defaultEngine(for: "rar"),
                "automatic mode did not use the catalog default"
            )

            store.isAutomatic = false
            #expect(store.selectedEngine(for: "rar") == .xad, "the override did not come back")
        }

        /// Automatic mode follows the catalog default, so moving that default is
        /// what changes which engine runs — the hook the fallback tests use.
        @Test func automaticFollowsTheCatalogDefault() {
            let catalog = ArchiveTypeCatalogWithDefault(["rar": .xad])
            let store = ArchiveEngineConfigStore(catalog: catalog, defaults: isolatedDefaults())
            store.isAutomatic = true
            #expect(store.selectedEngine(for: "rar") == .xad)
        }

        // MARK: - Which mode allows a fallback

        /// The whole point of the toggle: only automatic mode may switch engines.
        @Test func onlyAutomaticModeAllowsFallback() {
            let catalog = ArchiveTypeCatalog()
            let store = ArchiveEngineConfigStore(catalog: catalog, defaults: isolatedDefaults())
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
        }
    }
}
