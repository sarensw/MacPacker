//
//  AppUrlExtractToFolderHandler.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 24.09.25.
//

import Foundation
import Core
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "url")

class AppUrlExtractToFolderHandler: AppUrlHandler {
    private let catalog: ArchiveTypeCatalog
    private let engineSelector: ArchiveEngineSelectorProtocol
    
    init(catalog: ArchiveTypeCatalog, engineSelector: ArchiveEngineSelectorProtocol) {
        self.catalog = catalog
        self.engineSelector = engineSelector
    }
    
    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) {
        for fileUrl in appUrl.files {
            log.debug("Extracting \(fileUrl) to folder \(appUrl.target)")
            
            requestAccessToDir(for: appUrl.target) { response, url in
                if response == .OK {
                    if let url {
                        let folderName = ArchiveTypeDetector(catalog: self.catalog).getNameWithoutExtension(for: url)
                        let folderUrl = url.appendingPathComponent(folderName)
                        do {
                            try FileManager.default.createDirectory(
                                at: folderUrl,
                                withIntermediateDirectories: true
                            )
                            
                            log.debug("Found archive handler for \(fileUrl.lastPathComponent)")
                            
                            Task {
                                // The loader resolves a split to its first volume and
                                // asks for source-folder access itself, via the
                                // provider — like a password. We just hand it the file.
                                let state = ArchiveState(catalog: self.catalog, engineSelector: self.engineSelector)
                                state.folderAccessProvider = { await FolderAccessStore.shared.ensureAccess(forFileIn: $0) }
                                state.open(url: fileUrl)
                                try await state.openTask?.value
                                state.extract(to: folderUrl)
                            }
                        } catch {
                            log.error(error.localizedDescription)
                        }
                    }
                }
            }
        }
    }
}
