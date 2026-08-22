//
//  AppUrlCompressHandler.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 16.07.26.
//

import AppKit
import Core
import Foundation
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "url")

/// Finder action "Compress to <name>.zip": creates the zip next to the
/// selected files without further questions (one folder-access prompt is
/// unavoidable under the sandbox).
class AppUrlCompressHandler: AppUrlHandler {
    private let catalog: ArchiveTypeCatalog
    private let engineSelector: ArchiveEngineSelectorProtocol

    init(catalog: ArchiveTypeCatalog, engineSelector: ArchiveEngineSelectorProtocol) {
        self.catalog = catalog
        self.engineSelector = engineSelector
    }

    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) {
        log.notice("Compress handler: \(appUrl.files.count) file(s)", context: ["target": appUrl.target.path])

        // access to the folder covers reading the inputs and writing the zip
        requestAccessToDir(for: appUrl.target) { response, grantedUrl in
            guard response == .OK, let dir = grantedUrl else {
                log.error("Sandbox access not granted for \(appUrl.target.path) — cannot compress")
                return
            }
            Task { @MainActor in
                let dest = CompressDestination.unique(
                    named: CompressDestination.name(files: appUrl.files, target: appUrl.target),
                    in: dir
                )
                log.notice("Compressing to \(dest.lastPathComponent)")

                // a headless state gives us the same add/save path the UI uses
                let state = ArchiveState(catalog: self.catalog, engineSelector: self.engineSelector)
                state.create()
                for file in appUrl.files {
                    state.add(url: file)
                }
                await state.save(to: dest)?.value

                if let error = state.error {
                    log.error("Compress failed", context: ["error": error])
                } else {
                    log.notice("Compress done", context: ["file": dest.lastPathComponent])
                    NSWorkspace.shared.activateFileViewerSelecting([dest])
                }
            }
        }
    }
}

/// Finder action "Add to Archive…": opens a new-archive window pre-filled
/// with the selection; the user picks name/format/level on save.
class AppUrlAddToArchiveHandler: AppUrlHandler {

    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) {
        log.notice("Add-to-archive handler: \(appUrl.files.count) file(s)")

        // the selected files live in the target folder — one folder grant
        // makes them readable for the later save
        requestAccessToDir(for: appUrl.target) { response, grantedUrl in
            guard response == .OK, grantedUrl != nil else {
                log.error("Sandbox access not granted for \(appUrl.target.path) — cannot add to archive")
                return
            }
            Task { @MainActor in
                archiveWindowManager.openCreateArchiveWindow(with: appUrl.files)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
