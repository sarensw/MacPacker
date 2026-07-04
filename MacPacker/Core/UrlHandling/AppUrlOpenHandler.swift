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
    private let catalog: ArchiveTypeCatalog

    init(catalog: ArchiveTypeCatalog) {
        self.catalog = catalog
    }

    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) {
        log.notice("Open handler: \(appUrl.files.count) file(s) to open")
        for fileUrl in appUrl.files {
            // A split part (`.z01`, `.zip.001`) needs *folder* access, which the
            // loader requests downstream — asking for single-file access here would
            // be a wasted, extra prompt. The detector recognizes such a part by its
            // extension alone (no read needed).
            if ArchiveTypeDetector(catalog: catalog).detect(for: fileUrl)?.split != nil {
                log.notice("Split archive; loader will request folder access for \(fileUrl.lastPathComponent)")
                archiveWindowManager.openArchiveWindow(for: fileUrl)
                continue
            }

            // A plain archive on the Finder-extension path has no ambient sandbox
            // access — request the single file.
            log.notice("Requesting sandbox access for \(fileUrl.lastPathComponent)")
            requestAccessToFile(for: fileUrl) { response, url in
                guard response == .OK, let url else {
                    log.error("Sandbox access not granted for \(fileUrl.lastPathComponent) (response \(response.rawValue)) — archive cannot be read")
                    return
                }
                DispatchQueue.main.async {
                    log.notice("Access granted, opening window for \(url.lastPathComponent)")
                    archiveWindowManager.openArchiveWindow(for: url)
                }
            }
        }
    }
}
