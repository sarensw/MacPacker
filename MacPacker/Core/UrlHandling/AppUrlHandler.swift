//
//  AppUrlHandler.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 24.09.25.
//

import AppKit
import Combine
import Core
import FinderMenu
import Foundation
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "url")

@MainActor
protocol AppUrlHandler {
    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) async
}

extension AppUrlHandler {
    /// Opens `archive`, extracts all of it into `destination` and waits for
    /// the job to end. Returns what the extraction added to `destination`, so
    /// the caller can select it in Finder.
    ///
    /// `smart` is the caller's: an entry that already created the folder it
    /// named passes `false`, so the extraction does not wrap a second one.
    ///
    /// "Added" is found by comparing the folder before and after rather than
    /// by predicting names, so it stays right however the extraction names
    /// what it creates.
    func extractArchive(
        _ archive: URL,
        into destination: URL,
        smart: Bool,
        destinationIsArchiveFolder: Bool = false,
        catalog: ArchiveTypeCatalog,
        engineSelector: ArchiveEngineSelectorProtocol
    ) async -> [URL] {
        // The loader resolves a split to its first volume and asks for
        // source-folder access itself, via the provider — like a password.
        let state = ArchiveState(catalog: catalog, engineSelector: engineSelector)
        // The public URL scheme cannot authenticate Finder as the caller.
        // Keep confirmation on unless the user explicitly disables it.
        if Keys.confirmsTrashAfterExtraction() {
            state.sourceCleanupAuthorizationProvider = { sources in
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = String(localized: "Move extracted archives to Trash?", comment: "Confirm source cleanup for a public URL extraction request")
                alert.informativeText = sources.map(\.lastPathComponent).joined(separator: "\n")
                alert.addButton(withTitle: String(localized: "Keep Archives", comment: "Keep source archives after extraction"))
                alert.addButton(withTitle: String(localized: "Move to Trash", comment: "Confirm moving extracted source archives to Trash"))
                NSApp.activate(ignoringOtherApps: true)
                return alert.runModal() == .alertSecondButtonReturn
            }
        }
        state.extractionDestinationIsArchiveFolder = destinationIsArchiveFolder
        state.extractionBackupWarningProvider = { ExtractionConflictPrompt.showRetainedBackup($0) }
        state.extractionConflictProvider = { await ExtractionConflictPrompt.request($0) }
        state.folderAccessProvider = { await FolderAccessStore.shared.ensureAccess(forFileIn: $0) }
        let passwords = FinderPasswordPrompt()
        state.passwordProvider = { await passwords.request($0) }
        state.open(url: archive)
        do {
            try await state.openTask?.value
        } catch {
            log.error("Could not open \(archive.lastPathComponent)", context: ["error": error.localizedDescription])
            if !passwords.wasCancelled {
                reportFailure(error.localizedDescription, archive: archive, destination: destination)
            }
            return []
        }
        guard !passwords.wasCancelled else { return [] }
        if let error = state.error {
            reportFailure(error, archive: archive, destination: destination)
            return []
        }

        let before = Set(folderContents(destination))
        let topLevel = state.root?.children?.compactMap { state.entries[$0]?.name } ?? []

        // extract(to:) raises isBusy before it returns and lowers it once the
        // job ends — done, cancelled or failed
        state.extract(to: destination, smart: smart)
        for await busy in state.$isBusy.values where !busy {
            break
        }

        guard let output = state.extractionOutput else { return [] }
        if output != destination { return [output] }
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

    /// Loading and destination errors happen before extraction has a job of
    /// its own. Keep them visible even when there is no main archive window.
    func reportFailure(_ message: String, archive: URL, destination: URL?) {
        let center = ExtractionProgressCenter.shared
        let job = center.begin(archiveName: archive.lastPathComponent, destination: destination,
                               itemCount: 0, totalBytes: nil)
        center.finish(job, .failed(message))
    }
}

private func folderContents(_ folder: URL) -> [URL] {
    (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
}
