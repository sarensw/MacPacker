//
//  ArchiveWindowManager.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 24.09.25.
//

import AppKit
import Foundation
import Core
import SwiftUI
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "lifecycle")

@MainActor
class ArchiveWindowManager {
    private var windowControllers: [ArchiveWindowController] = []
    private let appState: AppState
    
    /// Default constructor
    /// - Parameter appState: The apps global state to not use AppStorage for every little global state setting that is not persisted
    init(appState: AppState) {
        self.appState = appState
        log.notice("ArchiveWindowManager initialised")
    }
    
    /// Creates a new archive window and loads the archive from the given url if available
    /// - Parameter url: url of the archive
    fileprivate func createAndShowArchiveWindow(_ url: URL?) {
        log.notice("Creating window", context: ["url": url?.lastPathComponent ?? "(empty)"])
        // every window has an archive state which defines both empty
        // (not yet loaded archives) or loaded archives
        let archiveState = ArchiveState(
            catalog: appState.catalog,
            engineSelector: appState.engineSelector
        )
        // The loader asks for folder access through this when it hits a split
        // archive — exactly like it asks for a password. The app fulfills it.
        archiveState.folderAccessProvider = { await FolderAccessStore.shared.ensureAccess(forFileIn: $0) }
        if let url {
            archiveState.open(url: url)
        }
        
        // create the window and place the archive state in it to check
        // later if there is a window without archive that could be used
        // to open a new archive
        let archiveWindowController = ArchiveWindowController(
            archiveState: archiveState,
            appState: appState
        )
        windowControllers.append(archiveWindowController)
        archiveWindowController.willCloseHandler = { [weak self] in
            self?.windowControllers.removeAll { $0 === archiveWindowController }
        }
        archiveWindowController.showWindow(nil)
    }
    
    /// During launch two things might happen. Either the app is launched with a url (e.g. via the Open With... menu
    /// or without. The order of `application(_:open:)` and `applicationDidFinishLaunching` is not
    /// guaranteed. That's why `openLaunchArchiveWindow` is only called once when the app launches
    /// and only creates an empty window in case the app was not launched with a url.
    func openLaunchArchiveWindow() {
        log.notice("openLaunchArchiveWindow (existing windows: \(windowControllers.count))")
        if windowControllers.isEmpty {
            createAndShowArchiveWindow(nil)
        }
    }
    
    /// Creates a new empty window, or shows an existing empty window where no archive is loaded or created yet
    func openArchiveWindow() {
        if let ewc = windowControllers.first(where: { $0.archiveState.hasArchive == false }) {
            ewc.showWindow(nil)
        } else {
            createAndShowArchiveWindow(nil)
        }
    }
    
    /// Opens a new empty window, regardless of whether there is any other window open right now
    func openNewArchiveWindow() {
        createAndShowArchiveWindow(nil)
    }
    
    /// Shows a window for `url`. Just window management — the loader resolves the
    /// real archive (unwrapping compounds, reducing a split to its first volume) and
    /// asks for folder access itself. Dedup is by the split-aware **canonical label**,
    /// so opening any volume of a set (`.z01`, `.z05`, the bare `.zip`) focuses the
    /// one window rather than opening duplicates.
    ///
    /// 1. archive already loaded: focus that window (don't reload)
    /// 2. an empty window exists: reuse it
    /// 3. otherwise: create a new window
    func openArchiveWindow(for url: URL) {
        let key = windowKey(for: url)
        if let wc = windowControllers.first(where: {
            guard let existing = $0.archiveState.url else { return false }
            // case-insensitive: matches the (default) case-insensitive filesystem.
            return windowKey(for: existing).path.caseInsensitiveCompare(key.path) == .orderedSame
        }) {
            log.notice("Archive already open, focusing existing window for \(url.lastPathComponent)")
            wc.showWindow(nil)
        } else if let ewc = windowControllers.first(where: { $0.archiveState.hasArchive == false }) {
            log.notice("Reusing empty window to open \(url.lastPathComponent)")
            ewc.archiveState.open(url: url)
            ewc.showWindow(nil)
        } else {
            log.notice("Opening a new window for \(url.lastPathComponent)")
            createAndShowArchiveWindow(url)
        }
    }

    /// The window's dedup identity: every volume of a split set reduces to one
    /// lexical key (spanned parts *and* the bare `.zip` → `<base>.zip`, numeric →
    /// `<base>.zip.001`) via the catalog's split rules, so opening any part focuses
    /// one window. Non-split urls are their own key.
    private func windowKey(for url: URL) -> URL {
        let name = url.lastPathComponent
        for split in appState.catalog.allSplits()
        where name.range(of: split.pattern, options: [.regularExpression, .caseInsensitive]) != nil {
            let keyName = name.replacingOccurrences(
                of: split.pattern, with: split.label,
                options: [.regularExpression, .caseInsensitive])
            return url.deletingLastPathComponent().appendingPathComponent(keyName)
        }
        return url
    }
}
