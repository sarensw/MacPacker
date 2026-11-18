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
/// new folder named after it, next to it, then selects in Finder those in the
/// window's own folder. A folder that nothing was extracted into is removed
/// again.
class AppUrlExtractToFolderHandler: AppUrlHandler {
    private let catalog: ArchiveTypeCatalog
    private let engineSelector: ArchiveEngineSelectorProtocol
    
    init(catalog: ArchiveTypeCatalog, engineSelector: ArchiveEngineSelectorProtocol) {
        self.catalog = catalog
        self.engineSelector = engineSelector
    }
    
    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) async {
        log.debug("Extracting \(appUrl.files.count) archive(s) to folders in \(appUrl.target)")

        // Each folder goes next to its archive: in the window's folder, or in a
        // folder expanded in it. One grant on the window's folder covers both.
        for folder in Set(appUrl.files.map(appUrl.folder(of:))).sorted(by: { $0.path < $1.path }) {
            guard await FolderAccessStore.shared.ensureAccess(forFolder: folder) else {
                log.error("No access to \(folder.lastPathComponent) — cannot extract")
                return
            }
        }
        var folders: [URL] = []
        for fileUrl in appUrl.files {
            // A folder that cannot be created is a failed job already. It goes
            // next to the archive: in the window's folder, or in one expanded
            // in it.
            guard let folderUrl = ExtractToFolder.makeFolder(
                for: fileUrl, in: appUrl.folder(of: fileUrl), catalog: self.catalog) else {
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
        // only where it takes no second Finder window
        let selected = appUrl.itemsToSelect(folders)
        if !selected.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(selected)
        }
    }
}
