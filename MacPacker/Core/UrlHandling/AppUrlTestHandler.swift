//
//  AppUrlTestHandler.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 04.11.26.
//

import Core
import FinderMenu
import Foundation
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "url")

/// Finder action "Test Archive": checks every selected archive without
/// extracting anything. Each verdict stays in the progress window until it
/// is closed.
class AppUrlTestHandler: AppUrlHandler {
    private let catalog: ArchiveTypeCatalog
    private let engineSelector: ArchiveEngineSelectorProtocol

    init(catalog: ArchiveTypeCatalog, engineSelector: ArchiveEngineSelectorProtocol) {
        self.catalog = catalog
        self.engineSelector = engineSelector
    }

    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) async {
        log.notice("Test handler: \(appUrl.files.count) archive(s)")

        // the selected archives share one folder: a single grant covers them all
        guard await FolderAccessStore.shared.ensureAccess(forFolder: appUrl.target) else {
            log.error("No access to \(appUrl.target.lastPathComponent) — cannot test")
            return
        }
        for fileUrl in appUrl.files {
            let state = ArchiveState(catalog: catalog, engineSelector: engineSelector)
            // the other volumes of a split, and a password, are asked for as when opening
            state.folderAccessProvider = { await FolderAccessStore.shared.ensureAccess(forFileIn: $0) }
            state.passwordProvider = { @MainActor request in await PasswordWindow.ask(request) }
            await state.test(fileUrl).value
        }
    }
}
