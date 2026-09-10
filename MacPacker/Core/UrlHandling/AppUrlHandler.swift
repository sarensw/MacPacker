//
//  AppUrlHandler.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 24.09.25.
//

import AppKit
import Combine
import Core
import Foundation
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "url")

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
        let message = String(localized: "\(Constants.appName) needs access to \(fileUrl.lastPathComponent)", comment: "Message in the file- and folder-access panel explaining why permission is required. The first placeholder is the app name MacPacker, the second is the name of the file or folder that needs access.")
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseFiles = dirHint == .notDirectory
        openPanel.canChooseDirectories = dirHint == .isDirectory
        openPanel.allowsOtherFileTypes = false
        openPanel.prompt = String(localized: "Grant Access", comment: "Confirmation button in the file- and folder-access panel")
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

    /// Opens `archive`, extracts all of it into `destination` and waits for
    /// the job to end. Returns what the extraction added to `destination`, so
    /// the caller can select it in Finder.
    ///
    /// "Added" is found by comparing the folder before and after rather than
    /// by predicting names, so it stays right however the extraction names
    /// what it creates.
    func extractArchive(
        _ archive: URL,
        into destination: URL,
        catalog: ArchiveTypeCatalog,
        engineSelector: ArchiveEngineSelectorProtocol
    ) async -> [URL] {
        // The loader resolves a split to its first volume and asks for
        // source-folder access itself, via the provider — like a password.
        let state = ArchiveState(catalog: catalog, engineSelector: engineSelector)
        state.folderAccessProvider = { await FolderAccessStore.shared.ensureAccess(forFileIn: $0) }
        state.open(url: archive)
        do {
            try await state.openTask?.value
        } catch {
            log.error("Could not open \(archive.lastPathComponent)", context: ["error": error.localizedDescription])
            return []
        }

        let before = Set(folderContents(destination))
        let topLevel = state.root?.children?.compactMap { state.entries[$0]?.name } ?? []

        // extract(to:) raises isBusy before it returns and lowers it once the
        // job ends — done, cancelled or failed
        state.extract(to: destination)
        for await busy in state.$isBusy.values where !busy {
            break
        }

        let added = folderContents(destination).filter { !before.contains($0) }
        if !added.isEmpty {
            return added
        }
        // extracted over existing items: nothing is new, so point at what the
        // archive holds
        return topLevel
            .map { destination.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}

private func folderContents(_ folder: URL) -> [URL] {
    (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
}
