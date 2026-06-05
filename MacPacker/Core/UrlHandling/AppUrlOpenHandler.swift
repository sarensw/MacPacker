//
//  AppUrlOpenHandler.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 24.09.25.
//

import AppKit
import Core
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "url")

class AppUrlOpenHandler: AppUrlHandler {
    
    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) {
        log.notice("Open handler: \(appUrl.files.count) file(s) to open")
        for fileUrl in appUrl.files {
            log.notice("Requesting sandbox access for \(fileUrl.lastPathComponent)")

            requestAccessToFile(for: fileUrl, completion: { response, url in
                guard response == .OK, let url else {
                    log.error("Sandbox access not granted for \(fileUrl.lastPathComponent) (response \(response.rawValue)) — archive cannot be read")
                    return
                }

                DispatchQueue.main.async {
                    log.notice("Access granted, opening window for \(url.lastPathComponent)")
                    archiveWindowManager.openArchiveWindow(for: url)
                }
            })
        }
    }
}
