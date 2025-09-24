//
//  AppUrlOpenHandler.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 24.09.25.
//

import AppKit

class AppUrlOpenHandler: AppUrlHandler {
    
    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) {
        for fileUrl in appUrl.files {
            Logger.log("Requesting access for \(fileUrl)")
            
            requestAccessToFile(for: fileUrl, completion: { response, url in
                if response == .OK {
                    Logger.log("want to open for \(String(describing: url))")
                    archiveWindowManager.openArchiveWindow(for: url)
                }
            })
        }
    }
}
