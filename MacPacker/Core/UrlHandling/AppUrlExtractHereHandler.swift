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
/// then selects in Finder what came out in the window's own folder.
class AppUrlExtractHereHandler: AppUrlHandler {
    private let catalog: ArchiveTypeCatalog
    private let engineSelector: ArchiveEngineSelectorProtocol
    
    init(catalog: ArchiveTypeCatalog, engineSelector: ArchiveEngineSelectorProtocol) {
        self.catalog = catalog
        self.engineSelector = engineSelector
    }
    
    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) async {
        log.debug("Extracting \(appUrl.files.count) archive(s) here: \(appUrl.target)")

        // Each archive goes next to itself: in the window's folder, or in a
        // folder expanded in it. A grant covers reading an archive and writing
        // next to it, and is asked for only when no stored one covers it —
        // one on the window's folder covers those expanded in it.
        for folder in Set(appUrl.files.map(appUrl.folder(of:))).sorted(by: { $0.path < $1.path }) {
            guard await FolderAccessStore.shared.ensureAccess(forFolder: folder) else {
                log.error("No access to \(folder.lastPathComponent) — cannot extract here")
                return
            }
        }
        var extracted: [URL] = []
        for fileUrl in appUrl.files {
            extracted += await self.extractArchive(fileUrl, into: appUrl.folder(of: fileUrl), smart: appUrl.action.honorsSmartExtraction && Keys.smartExtractionEnabled(), catalog: self.catalog, engineSelector: self.engineSelector)
        }
        // only where it takes no second Finder window
        let selected = appUrl.itemsToSelect(extracted)
        if !selected.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(selected)
        }
    }
}
