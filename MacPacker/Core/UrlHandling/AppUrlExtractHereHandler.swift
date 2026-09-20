//
//  AppUrlExtractHereHandler.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 24.09.25.
//

import AppKit
import Core
import FinderMenu
import Foundation
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "url")

/// Finder action "Extract Here": extracts every selected archive next to it,
/// then selects what came out in Finder.
class AppUrlExtractHereHandler: AppUrlHandler {
    private let catalog: ArchiveTypeCatalog
    private let engineSelector: ArchiveEngineSelectorProtocol
    
    init(catalog: ArchiveTypeCatalog, engineSelector: ArchiveEngineSelectorProtocol) {
        self.catalog = catalog
        self.engineSelector = engineSelector
    }
    
    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) {
        log.debug("Extracting \(appUrl.files.count) archive(s) here: \(appUrl.target)")

        // the selected archives share one folder: a single grant covers
        // reading them and writing next to them, and it is asked for only
        // when no stored grant covers it already
        Task { @MainActor in
            guard await FolderAccessStore.shared.ensureAccess(forFolder: appUrl.target) else {
                log.error("No access to \(appUrl.target.lastPathComponent) — cannot extract here")
                return
            }
            var extracted: [URL] = []
            for fileUrl in appUrl.files {
                extracted += await self.extractArchive(fileUrl, into: appUrl.target, smart: appUrl.action.honorsSmartExtraction && Keys.smartExtractionEnabled(), catalog: self.catalog, engineSelector: self.engineSelector)
            }
            if !extracted.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(extracted)
            }
        }
    }
}
