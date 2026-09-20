//
//  AppUrlOpenHandler.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 24.09.25.
//

import AppKit
import Core
import FinderMenu
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "url")

class AppUrlOpenHandler: AppUrlHandler {

    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) {
        log.notice("Open handler: \(appUrl.files.count) file(s) to open")
        // Nothing arrives with ambient access on the Finder-extension path: the
        // extension hands over paths, not a grant. Ask for the archive's *folder*
        // rather than the file — it is the same single panel, and it covers the
        // sibling volumes of a split archive, saving in place, and every further
        // archive in that folder, which a file grant does not.
        //
        // One task for the whole selection, not one per file: the files are
        // usually in the same folder, and asked for in parallel each would put
        // up its own panel before any of them had stored the grant. Serialized,
        // the first answer covers the rest. A refused one skips only itself.
        Task { @MainActor in
            for fileUrl in appUrl.files {
                guard await FolderAccessStore.shared.ensureAccess(forFileIn: fileUrl) else {
                    log.error("No access to \(fileUrl.lastPathComponent) — archive cannot be read")
                    continue
                }
                archiveWindowManager.openArchiveWindow(for: fileUrl)
            }
        }
    }
}
