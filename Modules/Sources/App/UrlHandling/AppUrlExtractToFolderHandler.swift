//
//  AppUrlExtractToFolderHandler.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 24.09.25.
//

import Foundation
import Core

class AppUrlExtractToFolderHandler: AppUrlHandler {
    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) {
        for fileUrl in appUrl.files {
            Logger.log("Extracting \(fileUrl) to folder \(appUrl.target)")
            
            requestAccessToDir(for: appUrl.target) { response, url in
                if response == .OK {
                    if let url {
                        let folderName = ArchiveTypeDetector().getNameWithoutExtension(for: url)
                        let folderUrl = url.appendingPathComponent(folderName)
                        do {
                            try FileManager.default.createDirectory(
                                at: folderUrl,
                                withIntermediateDirectories: true
                            )
                            
                            Logger.log("Found archive handler for \(fileUrl.lastPathComponent)")
                            
                            // TODO: Reenable
                            fatalError("Reenable")
//                            let state = ArchiveState()
//                            state.open(url: fileUrl)
//                            state.extract(to: folderUrl)
                        } catch {
                            Logger.error(error.localizedDescription)
                        }
                    }
                }
            }
        }
    }
}
