//
//  AppUrlChecksumHandler.swift
//  MacPacker
//

import Core
import FinderMenu
import Foundation
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "url")

/// Finder's file-checksum actions share one window; Verify starts with the
/// clipboard value, and Checksums starts with a blank comparison field.
class AppUrlChecksumHandler: AppUrlHandler {
    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) {
        Task { @MainActor in
            var checkedFolders: Set<URL> = []
            for file in appUrl.files {
                let folder = file.deletingLastPathComponent()
                guard checkedFolders.insert(folder).inserted else { continue }
                guard await FolderAccessStore.shared.ensureAccess(forFolder: folder) else {
                    log.error("No access to \(folder.lastPathComponent) — cannot calculate checksums")
                    return
                }
            }
            ChecksumWindowController.show(
                files: appUrl.files,
                verifyFromClipboard: appUrl.action == .verifyChecksum
            )
        }
    }
}
