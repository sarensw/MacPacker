//
//  AppUrlExtractHereHandler.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 24.09.25.
//

import Core

class AppUrlExtractHereHandler: AppUrlHandler {
    private let catalog: ArchiveTypeCatalog
    private let engineSelector: ArchiveEngineSelectorProtocol
    
    init(catalog: ArchiveTypeCatalog, engineSelector: ArchiveEngineSelectorProtocol) {
        self.catalog = catalog
        self.engineSelector = engineSelector
    }
    
    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) {
        for fileUrl in appUrl.files {
            Logger.log("Extracting \(fileUrl) here... \(appUrl.target)")
            
            requestAccessToDir(for: appUrl.target) { response, url in
                if response == .OK {
                    Logger.log("Found archive handler for \(fileUrl.lastPathComponent)")
                    if let url {
                        Task {
                            let state = ArchiveState(catalog: self.catalog, engineSelector: self.engineSelector)
                            state.open(url: fileUrl)
                            try await state.openTask?.value
                            state.extract(to: url)
                        }
                    }
                }
            }
        }
    }
}
