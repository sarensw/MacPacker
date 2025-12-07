//
//  AppUrlHandler.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 24.09.25.
//

import Foundation
import AppKit

@MainActor
protocol AppUrlHandler {
    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager)
}

extension AppUrlHandler {
    func requestAccess(
        for fileUrl: URL,
        dirHint: URL.DirectoryHint,
        completion: @escaping (NSApplication.ModalResponse, URL?) -> Void
    ) {
        let message = "MacPacker needs access to \(fileUrl.lastPathComponent)"
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseFiles = dirHint == .notDirectory
        openPanel.canChooseDirectories = dirHint == .isDirectory
        openPanel.allowsOtherFileTypes = false
        openPanel.prompt = "Give access to MacPacker"
        openPanel.message = message
        openPanel.directoryURL = fileUrl
        openPanel.level = .floating
        openPanel.begin() { response in
            completion(response, openPanel.url)
        }
    }
    
    func requestAccessToFile(
        for fileUrl: URL,
        completion: @escaping (NSApplication.ModalResponse, URL?) -> Void
    ) {
        requestAccess(
            for: fileUrl,
            dirHint: .notDirectory,
            completion: completion
        )
    }
    
    func requestAccessToDir(
        for fileUrl: URL,
        completion: @escaping (NSApplication.ModalResponse, URL?) -> Void
    ) {
        requestAccess(
            for: fileUrl,
            dirHint: .isDirectory,
            completion: completion
        )
    }
}
