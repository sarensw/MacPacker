//
//  AppUrlExtractHereHandler.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 24.09.25.
//

import Core

class AppUrlExtractHereHandler: AppUrlHandler {
    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) {
        for fileUrl in appUrl.files {
            Logger.log("Extracting \(fileUrl) here... \(appUrl.target)")
            
            requestAccessToDir(for: appUrl.target) { response, url in
                if response == .OK {
                    Logger.log("Found archive handler for \(fileUrl.lastPathComponent)")
                    if let url {
                        let state = ArchiveState()
                        state.load(from: fileUrl)
                        state.extract(to: url)
                    }
                }
            }
        }
    }
}
