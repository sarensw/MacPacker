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
/// window's own folder.
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
            // The folder we create next to the archive is named after it,
            // so the name comes from `fileUrl`.
            let folderName = ArchiveTypeDetector(catalog: self.catalog).getNameWithoutExtension(for: fileUrl)
            let folderUrl = appUrl.folder(of: fileUrl).appendingPathComponent(folderName)
            do {
                try FileManager.default.createDirectory(at: folderUrl, withIntermediateDirectories: true)
            } catch {
                log.error(error.localizedDescription)
                continue
            }
            // `honorsSmartExtraction` is false for this action: the folder
            // it is named after has just been created, so wrapping a second
            // one inside would be the `Photos/Photos` nesting the smart rule
            // exists to avoid.
            _ = await self.extractArchive(fileUrl, into: folderUrl, smart: appUrl.action.honorsSmartExtraction && Keys.smartExtractionEnabled(), catalog: self.catalog, engineSelector: self.engineSelector)
            folders.append(folderUrl)
        }
        // only where it takes no second Finder window
        let selected = appUrl.itemsToSelect(folders)
        if !selected.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(selected)
        }
    }
}
