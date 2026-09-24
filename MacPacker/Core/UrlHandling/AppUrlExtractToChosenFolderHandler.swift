//
//  AppUrlExtractToChosenFolderHandler.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 10.09.26.
//

import AppKit
import Core
import FinderMenu
import Foundation
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "url")

/// Finder action "Extract to…": asks where to extract, extracts every
/// selected archive there, then selects what came out in Finder. Picking the folder also grants writing into it;
/// archives outside the picked folder need their own read grant, which the
/// folder-access store asks for only when no stored grant covers them.
class AppUrlExtractToChosenFolderHandler: AppUrlHandler {
    private let catalog: ArchiveTypeCatalog
    private let engineSelector: ArchiveEngineSelectorProtocol

    init(catalog: ArchiveTypeCatalog, engineSelector: ArchiveEngineSelectorProtocol) {
        self.catalog = catalog
        self.engineSelector = engineSelector
    }

    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) {
        log.notice("Extract-to handler: \(appUrl.files.count) archive(s)")

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = appUrl.target
        panel.prompt = String(localized: .commonExtract)
        panel.message = String(localized: .archiveExtractChooseDestination)
        panel.level = .floating
        NSApp.activate(ignoringOtherApps: true)

        panel.begin { response in
            guard response == .OK, let destination = panel.url else {
                log.notice("Extract-to cancelled")
                return
            }
            // Picking the folder *is* the grant — powerbox hands it over with
            // the pick — so this only has to keep it, and the next extraction
            // there needs no panel at all. `ensureAccess` is for the other
            // case: it sees no stored bookmark yet and would put a second
            // panel over the one the user just answered. It is used below,
            // where it belongs: on the archives' own folder.
            Sandbox.storeBookmark(url: destination)
            Task { @MainActor in
                if !FolderAccess.isInside(appUrl.target, destination),
                   let first = appUrl.files.first,
                   !(await FolderAccessStore.shared.ensureAccess(forFileIn: first)) {
                    log.error("No read access to the archives' folder — cannot extract")
                    return
                }
                var extracted: [URL] = []
                for fileUrl in appUrl.files {
                    extracted += await self.extractArchive(fileUrl, into: destination, smart: appUrl.action.honorsSmartExtraction && Keys.smartExtractionEnabled(), catalog: self.catalog, engineSelector: self.engineSelector)
                }
                if !extracted.isEmpty {
                    NSWorkspace.shared.activateFileViewerSelecting(extracted)
                }
            }
        }
    }
}
