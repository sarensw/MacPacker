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
            // archive, so the name comes from `fileUrl`. A folder of that
            // name already there is left alone: the new one is "name 2".
            let folderName = SmartExtraction.freeName(
                ArchiveTypeDetector(catalog: self.catalog).getNameWithoutExtension(for: fileUrl),
                in: appUrl.target, isDirectory: true)
            let folderUrl = appUrl.target.appendingPathComponent(folderName)
            do {
                // through the target's stored grant, which may be from an
                // earlier launch
                try Sandbox.accessSync(url: folderUrl) {
                    try FileManager.default.createDirectory(at: folderUrl, withIntermediateDirectories: true)
                }
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
        if !folders.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(folders)
        }
    }
}
