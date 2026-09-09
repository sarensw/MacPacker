//
//  AppState.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 22.04.26.
//

import Core
import SwiftUI
import tb
#if !STORE
import Sparkle
#endif

private let log = tb.Logger(subsystem: "app.MacPacker", category: "lifecycle")

final class AppState: ObservableObject {
#if !STORE
    let updaterController: SPUStandardUpdaterController?
#endif
    
    let catalog: ArchiveTypeCatalog = ArchiveTypeCatalog()
    let engineSelector: ArchiveEngineSelectorProtocol
    let archiveEngineConfigStore: ArchiveEngineConfigStore
    
    @Published var selectedSettingsTab: SettingsViewTab = .general

    /// The engine settings the QuickLook extension reads too, so a pick made
    /// here shows up in the preview. Only the app migrates the older, app-local
    /// settings into the shared store.
    private static func makeEngineConfigStore(catalog: ArchiveTypeCatalog) -> ArchiveEngineConfigStore {
        ArchiveEngineConfigStore.migrateToSharedDefaults()
        return ArchiveEngineConfigStore(catalog: catalog, defaults: .macPackerShared)
    }

#if !STORE
    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.archiveEngineConfigStore = AppState.makeEngineConfigStore(catalog: catalog)
        self.engineSelector = ArchiveEngineSelector(catalog: catalog, configStore: archiveEngineConfigStore)

        self.updaterController = updaterController
        log.notice("AppState ready (catalog + engine selector initialised)")
    }
#else
    init() {
        self.archiveEngineConfigStore = AppState.makeEngineConfigStore(catalog: catalog)
        self.engineSelector = ArchiveEngineSelector(catalog: catalog, configStore: archiveEngineConfigStore)
        log.notice("AppState ready (catalog + engine selector initialised)")
    }
#endif
}
