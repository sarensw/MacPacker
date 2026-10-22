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
/// new folder named after it, then selects those folders in Finder.
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
            // The folder we create in the target is named after the
            // archive, so the name comes from `fileUrl`.
            var folderName = ArchiveTypeDetector(catalog: self.catalog).getNameWithoutExtension(for: fileUrl)
            // A folder of that name is there already: kept as it is, with the
            // archive in a second one beside it, when Settings say keep both.
            // Otherwise extracted into, as before.
            if NameClash.current() == .keepBoth {
                folderName = NameClash.freeName(for: folderName, in: appUrl.target)
            }
            let folderUrl = appUrl.target.appendingPathComponent(folderName)
            // The folder is not created here. The extraction makes a
            // destination that is not there yet, and takes it back with a run
            // that does not finish — created up front, it stayed behind, empty,
            // after a cancel. A name that is taken by a file fails there too,
            // where it is reported, rather than here, where it was only logged.
            //
            // `honorsSmartExtraction` is false for this action: the folder
            // it is named after is the one extracted into, so wrapping a
            // second one inside would be the `Photos/Photos` nesting the smart
            // rule exists to avoid.
            _ = await self.extractArchive(fileUrl, into: folderUrl, smart: appUrl.action.honorsSmartExtraction && Keys.smartExtractionEnabled(), catalog: self.catalog, engineSelector: self.engineSelector)
            // only a folder that is there can be shown
            if FileManager.default.fileExists(atPath: folderUrl.path) {
                folders.append(folderUrl)
            }
        }
        if !folders.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(folders)
        }
    }
}
