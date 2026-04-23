//
//  AppState.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 22.04.26.
//

import Core
import SwiftUI
#if !STORE
import Sparkle
#endif

final class AppState: ObservableObject {
    let updaterController: SPUStandardUpdaterController?
    let catalog: ArchiveTypeCatalog = ArchiveTypeCatalog()
    let engineSelector: ArchiveEngineSelectorProtocol
    let archiveEngineConfigStore: ArchiveEngineConfigStore
    
    @Published var selectedSettingsTab: SettingsViewTab = .general
    
    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.archiveEngineConfigStore = ArchiveEngineConfigStore(catalog: catalog)
        self.engineSelector = ArchiveEngineSelector(catalog: catalog, configStore: archiveEngineConfigStore)
        
        self.updaterController = updaterController
    }
}
