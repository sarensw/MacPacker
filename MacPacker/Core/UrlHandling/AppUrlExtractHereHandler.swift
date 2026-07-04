//
//  AppUrlExtractHereHandler.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 24.09.25.
//

import Foundation
import Core
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "url")

class AppUrlExtractHereHandler: AppUrlHandler {
    private let catalog: ArchiveTypeCatalog
    private let engineSelector: ArchiveEngineSelectorProtocol
    
    init(catalog: ArchiveTypeCatalog, engineSelector: ArchiveEngineSelectorProtocol) {
        self.catalog = catalog
        self.engineSelector = engineSelector
    }
    
    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) {
        for fileUrl in appUrl.files {
            log.debug("Extracting \(fileUrl) here... \(appUrl.target)")
            
            requestAccessToDir(for: appUrl.target) { response, url in
                if response == .OK {
                    log.debug("Found archive handler for \(fileUrl.lastPathComponent)")
                    if let url {
                        Task {
                            // The loader resolves a split to its first volume and asks
                            // for source-folder access itself, via the provider — like
                            // a password. We just hand it the file.
                            let state = ArchiveState(catalog: self.catalog, engineSelector: self.engineSelector)
                            state.folderAccessProvider = { await FolderAccessStore.shared.ensureAccess(forFileIn: $0) }
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
