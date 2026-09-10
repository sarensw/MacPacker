//
//  AppUrlExtractToChosenFolderHandler.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 10.09.26.
//

import AppKit
import Core
import Foundation
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "url")

/// Whether `folder` is `ancestor` or lies somewhere inside it.
private func isInside(_ folder: URL, _ ancestor: URL) -> Bool {
    let f = folder.standardizedFileURL.path
    let a = ancestor.standardizedFileURL.path
    return f == a || f.hasPrefix(a + "/")
}

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
        panel.prompt = String(localized: "Extract", comment: "Prompt of the folder picker used to extract items")
        panel.message = String(localized: "Choose where to extract", comment: "Message of the panel that picks where to extract the archives selected in Finder")
        panel.level = .floating
        NSApp.activate(ignoringOtherApps: true)

        panel.begin { response in
            guard response == .OK, let destination = panel.url else {
                log.notice("Extract-to cancelled")
                return
            }
            Task { @MainActor in
                if !isInside(appUrl.target, destination),
                   let first = appUrl.files.first,
                   !(await FolderAccessStore.shared.ensureAccess(forFileIn: first)) {
                    log.error("No read access to the archives' folder — cannot extract")
                    return
                }
                var extracted: [URL] = []
                for fileUrl in appUrl.files {
                    extracted += await self.extractArchive(fileUrl, into: destination, catalog: self.catalog, engineSelector: self.engineSelector)
                }
                if !extracted.isEmpty {
                    NSWorkspace.shared.activateFileViewerSelecting(extracted)
                }
            }
        }
    }
}
