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
/// selected archive there, then selects in Finder what came out in the
/// window's own folder. Picking the folder also grants writing into it;
/// archives outside the picked folder need their own read grant, which the
/// folder-access store asks for only when no stored grant covers them.
class AppUrlExtractToChosenFolderHandler: AppUrlHandler {
    private let catalog: ArchiveTypeCatalog
    private let engineSelector: ArchiveEngineSelectorProtocol

    init(catalog: ArchiveTypeCatalog, engineSelector: ArchiveEngineSelectorProtocol) {
        self.catalog = catalog
        self.engineSelector = engineSelector
    }

    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) async {
        log.notice("Extract-to handler: \(appUrl.files.count) archive(s)")

        // the panel starts where Extract Here would put it: next to the archive
        let start = appUrl.files.first.map(appUrl.folder(of:)) ?? appUrl.target
        guard let destination = await chooseDestination(startingIn: start) else {
            log.notice("Extract-to cancelled")
            return
        }
        // Picking the folder *is* the grant — powerbox hands it over with
        // the pick — so this only has to keep it, and the next extraction
        // there needs no panel at all. `ensureAccess` is for the other
        // case: it sees no stored bookmark yet and would put a second
        // panel over the one the user just answered. It is used below,
        // where it belongs: on the archives' own folders, those the picked
        // one does not hold.
        Sandbox.storeBookmark(url: destination)
        for folder in Set(appUrl.files.map(appUrl.folder(of:))).sorted(by: { $0.path < $1.path })
        where !FolderAccess.isInside(folder, destination) {
            guard await FolderAccessStore.shared.ensureAccess(forFolder: folder) else {
                log.error("No read access to \(folder.lastPathComponent) — cannot extract")
                return
            }
        }
        var extracted: [URL] = []
        for fileUrl in appUrl.files {
            extracted += await self.extractArchive(fileUrl, into: destination, smart: appUrl.action.honorsSmartExtraction && Keys.smartExtractionEnabled(), catalog: self.catalog, engineSelector: self.engineSelector)
        }
        // only where it takes no second Finder window
        let selected = appUrl.itemsToSelect(extracted)
        if !selected.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(selected)
        }
    }

    /// Asks where to extract. `nil` when the panel is cancelled.
    private func chooseDestination(startingIn folder: URL) async -> URL? {
        await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.directoryURL = folder
            panel.prompt = String(localized: .commonExtract)
            panel.message = String(localized: .archiveExtractChooseDestination)
            panel.level = .floating
            NSApp.activate(ignoringOtherApps: true)

            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }
}
