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
    
    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) {
        log.debug("Extracting \(appUrl.files.count) archive(s) to folders in \(appUrl.target)")

        // the selected archives share one folder: a single grant covers them all
        requestAccessToDir(for: appUrl.target) { response, url in
            guard response == .OK, let url else { return }
            Task { @MainActor in
                var folders: [URL] = []
                for fileUrl in appUrl.files {
                    // `url` is the folder the user granted access to — the
                    // destination. The folder we create inside it is named
                    // after the archive, so the name comes from `fileUrl`.
                    let folderName = ArchiveTypeDetector(catalog: self.catalog).getNameWithoutExtension(for: fileUrl)
                    let folderUrl = url.appendingPathComponent(folderName)
                    do {
                        try FileManager.default.createDirectory(at: folderUrl, withIntermediateDirectories: true)
                    } catch {
                        log.error(error.localizedDescription)
                        continue
                    }
                    _ = await self.extractArchive(fileUrl, into: folderUrl, catalog: self.catalog, engineSelector: self.engineSelector)
                    folders.append(folderUrl)
                }
                if !folders.isEmpty {
                    NSWorkspace.shared.activateFileViewerSelecting(folders)
                }
            }
        }
    }
}
