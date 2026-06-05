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
    
#if !STORE
    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.archiveEngineConfigStore = ArchiveEngineConfigStore(catalog: catalog)
        self.engineSelector = ArchiveEngineSelector(catalog: catalog, configStore: archiveEngineConfigStore)

        self.updaterController = updaterController
        log.notice("AppState ready (catalog + engine selector initialised)")
    }
#else
    init() {
        self.archiveEngineConfigStore = ArchiveEngineConfigStore(catalog: catalog)
        self.engineSelector = ArchiveEngineSelector(catalog: catalog, configStore: archiveEngineConfigStore)
        log.notice("AppState ready (catalog + engine selector initialised)")
    }
#endif
}
