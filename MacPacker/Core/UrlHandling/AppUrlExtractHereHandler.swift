//
//  AppUrlExtractHereHandler.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 24.09.25.
//

class AppUrlExtractHereHandler: AppUrlHandler {
    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) {
        for fileUrl in appUrl.files {
            Logger.log("Extracting \(fileUrl) here... \(appUrl.target)")
            
            requestAccessToDir(for: appUrl.target) { response, url in
                if response == .OK {
                    if let url,
                       let archiveHandler = ArchiveHandlerRegistry.shared.handler(for: fileUrl)
                    {
                        Logger.log("Found archive handler for \(fileUrl.lastPathComponent)")
                        archiveHandler.extract(
                            archiveUrl: fileUrl,
                            to: url,
                        )
                    }
                }
            }
        }
    }
}
