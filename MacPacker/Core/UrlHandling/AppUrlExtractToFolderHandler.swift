//
//  AppUrlExtractToFolderHandler.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 24.09.25.
//

import Foundation
import Core

class AppUrlExtractToFolderHandler: AppUrlHandler {
    private let catalog: ArchiveTypeCatalog
    private let engineSelector: ArchiveEngineSelectorProtocol
    
    init(catalog: ArchiveTypeCatalog, engineSelector: ArchiveEngineSelectorProtocol) {
        self.catalog = catalog
        self.engineSelector = engineSelector
    }
    
    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) {
        for fileUrl in appUrl.files {
            Logger.log("Extracting \(fileUrl) to folder \(appUrl.target)")
            
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
                            
                            Logger.log("Found archive handler for \(fileUrl.lastPathComponent)")
                            
                            Task {
                                let state = ArchiveState(catalog: self.catalog, engineSelector: self.engineSelector)
                                state.open(url: fileUrl)
                                try await state.openTask?.value
                                state.extract(to: folderUrl)
                            }
                        } catch {
                            Logger.error(error.localizedDescription)
                        }
                    }
                }
            }
        }
    }
}
