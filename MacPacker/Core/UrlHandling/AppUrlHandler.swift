//
//  AppUrlHandler.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 24.09.25.
//

import AppKit
import Core
import FinderMenu
import Foundation
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "url")

@MainActor
protocol AppUrlHandler {
    /// Does all of the action's work, and returns when it is done.
    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) async
}

extension AppUrlHandler {
    /// Opens `archive`, extracts all of it into `destination` and waits for
    /// the job to end. Returns what the extraction added to `destination`, so
    /// the caller can select it in Finder. Extracting never writes over what
    /// is there, so that is nothing when it failed or was cancelled.
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
        catalog: ArchiveTypeCatalog,
        engineSelector: ArchiveEngineSelectorProtocol
    ) async -> [URL] {
        // The loader resolves a split to its first volume and asks for
        // source-folder access itself, via the provider — like a password.
        let state = ArchiveState(catalog: catalog, engineSelector: engineSelector)
        state.folderAccessProvider = { await FolderAccessStore.shared.ensureAccess(forFileIn: $0) }
        // Cancel ends the action. Opening goes on without a password, as a
        // zip lists its names without one, and extracting would ask again.
        let prompt = PasswordPrompt()
        state.passwordProvider = { @MainActor request in
            let password = await PasswordWindow.ask(request)
            if password == nil { prompt.wasCancelled = true }
            return password
        }
        state.open(url: archive)
        _ = try? await state.openTask?.value
        if prompt.wasCancelled {
            return []
        }
        // a failed open throws nothing: its reason is in openError, and the
        // extraction would only fail on the empty state with a reason of its own
        if let reason = state.openError {
            log.error("Could not open \(archive.lastPathComponent)", context: ["error": reason])
            let job = ExtractionProgressCenter.shared.begin(archiveName: archive.lastPathComponent, destination: destination, itemCount: 0, totalBytes: nil)
            ExtractionProgressCenter.shared.finish(job, .failed(reason))
            return []
        }

        let topLevel = state.root?.children?.compactMap { state.entries[$0]?.name } ?? []
        // inside the grant that covers the destination, held until the end;
        // what it put there — nothing, for a run that did not finish
        let (_, extracted) = await ExtractionFollowUp.extracting(into: destination, named: topLevel) {
            await state.extract(to: destination, smart: smart).value
        }
        return extracted
    }
}

/// Whether a password prompt was cancelled.
@MainActor
private final class PasswordPrompt {
    var wasCancelled = false
}
