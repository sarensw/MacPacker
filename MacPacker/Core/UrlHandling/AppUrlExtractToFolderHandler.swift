//
//  AppUrlExtractToFolderHandler.swift
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

/// Finder action "Extract to "<name>"": extracts each selected archive into a
/// new folder named after it, then selects those folders in Finder. A folder
/// that nothing was extracted into is removed again.
class AppUrlExtractToFolderHandler: AppUrlHandler {
    private let catalog: ArchiveTypeCatalog
    private let engineSelector: ArchiveEngineSelectorProtocol
    
    init(catalog: ArchiveTypeCatalog, engineSelector: ArchiveEngineSelectorProtocol) {
        self.catalog = catalog
        self.engineSelector = engineSelector
    }
    
    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) async {
        log.debug("Extracting \(appUrl.files.count) archive(s) to folders in \(appUrl.target)")

        // the selected archives share one folder: a single grant covers them all
        guard await FolderAccessStore.shared.ensureAccess(forFolder: appUrl.target) else {
            log.error("No access to \(appUrl.target.lastPathComponent) — cannot extract")
            return
        }
        var folders: [URL] = []
        for fileUrl in appUrl.files {
            // a folder that cannot be created is a failed job already
            guard let folderUrl = ExtractToFolder.makeFolder(for: fileUrl, in: appUrl.target, catalog: self.catalog) else {
                continue
            }
            // `honorsSmartExtraction` is false for this action: the folder
            // it is named after has just been created, so wrapping a second
            // one inside would be the `Photos/Photos` nesting the smart rule
            // exists to avoid.
            let added = await self.extractArchive(fileUrl, into: folderUrl, smart: appUrl.action.honorsSmartExtraction && Keys.smartExtractionEnabled(), catalog: self.catalog, engineSelector: self.engineSelector)
            // A failed or cancelled extraction adds nothing, and the folder
            // made for it goes again. rmdir removes it only while it is empty.
            if added.isEmpty && Sandbox.accessSync(url: folderUrl, perform: { rmdir(folderUrl.path) }) == 0 {
                continue
            }
            folders.append(folderUrl)
        }
        if !folders.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(folders)
        }
    }
}
