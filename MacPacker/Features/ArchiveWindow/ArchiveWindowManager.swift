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
    private let dropCompressor: DropCompressor
    private let openQuickCompressWindow: @MainActor () -> Void

    /// Default constructor
    /// - Parameters:
    ///   - appState: The apps global state to not use AppStorage for every little global state setting that is not persisted
    ///   - dropCompressor: The shared compressor every window's compress column renders
    ///   - openQuickCompressWindow: Opens the floating quick-compress window
    init(
        appState: AppState,
        dropCompressor: DropCompressor,
        openQuickCompressWindow: @escaping @MainActor () -> Void
    ) {
        self.appState = appState
        self.dropCompressor = dropCompressor
        self.openQuickCompressWindow = openQuickCompressWindow
        log.notice("ArchiveWindowManager initialised")
    }
    
    /// Creates a new archive window and loads the archive from the given url if available
    /// - Parameter url: url of the archive
    /// - Returns: the window's `ArchiveState`, so callers that need to drive it
    ///   (e.g. the debug screenshot launcher) can navigate and select afterwards.
    @discardableResult
    fileprivate func createAndShowArchiveWindow(_ url: URL?) -> ArchiveState {
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
        // Opening a plain (non-archive) entry hands it to the system editor.
        archiveState.openFileExternally = { NSWorkspace.shared.open($0) }
        if let url {
            archiveState.open(url: url)
        }
        
        // create the window and place the archive state in it to check
        // later if there is a window without archive that could be used
        // to open a new archive
        let archiveWindowController = ArchiveWindowController(
            archiveState: archiveState,
            appState: appState,
            dropCompressor: dropCompressor,
            openQuickCompressWindow: openQuickCompressWindow,
            openArchiveInNewWindow: { [weak self] url in
                self?.openDroppedInNewWindow(url)
            },
            cascadeFrom: modelWindow
        )
        windowControllers.append(archiveWindowController)
        archiveWindowController.willCloseHandler = { [weak self] in
            self?.windowControllers.removeAll { $0 === archiveWindowController }
        }
        archiveWindowController.showWindow(nil)
        return archiveState
    }

    /// The window a new one models itself on. Falls back to the newest when no
    /// window is main (Finder's "Add to Archive…" keeps focus). Nil when none are
    /// open — the new window then uses the remembered frame.
    private var modelWindow: NSWindow? {
        windowControllers.first { $0.window?.isMainWindow == true }?.window
            ?? windowControllers.last?.window
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

    /// A file dropped on the "open in a new window" zone of a window that is
    /// already busy: an archive opens, anything else starts a new archive holding
    /// it — the same rule an empty window applies (`ArchiveState.openDropped`).
    func openDroppedInNewWindow(_ url: URL) {
        if ArchiveTypeDetector(catalog: appState.catalog).detect(for: url) != nil {
            openArchiveWindow(for: url)
        } else {
            openCreateArchiveWindow(with: [url])
        }
    }

    /// Opens a window with a fresh, empty archive in edit mode — optionally
    /// pre-filled with files (used by the Finder "Add to Archive…" action).
    /// The archive gets its place on disk when the user saves.
    @discardableResult
    func openCreateArchiveWindow(with files: [URL] = []) -> ArchiveState {
        let state = createAndShowArchiveWindow(nil)
        state.create(named: String(localized: "New Archive", comment: "File menu entry that opens a window with a new, empty archive ready to be filled and saved"))
        for file in files {
            state.add(url: file)
        }
        return state
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
    ///
    /// Returns the window's `ArchiveState`, so a caller that opened the archive
    /// on purpose (e.g. via launch parameters) can drive it afterwards —
    /// navigate to a path, select an item.
    @discardableResult
    func openArchiveWindow(for url: URL) -> ArchiveState {
        let state = showWindow(for: url)
        // Home-screen recents. Only real archives — an "Open With" on a plain file
        // ends up in a new archive, which isn't something to reopen later.
        if state.isSupportedArchive(url: url) { RecentArchives.note(url) }
        return state
    }

    private func showWindow(for url: URL) -> ArchiveState {
        let key = windowKey(for: url)
        if let wc = windowControllers.first(where: {
            guard let existing = $0.archiveState.url else { return false }
            // case-insensitive: matches the (default) case-insensitive filesystem.
            return windowKey(for: existing).path.caseInsensitiveCompare(key.path) == .orderedSame
        }) {
            log.notice("Archive already open, focusing existing window for \(url.lastPathComponent)")
            wc.showWindow(nil)
            return wc.archiveState
        } else if let ewc = windowControllers.first(where: { $0.archiveState.hasArchive == false }) {
            log.notice("Reusing empty window to open \(url.lastPathComponent)")
            ewc.archiveState.open(url: url)
            ewc.showWindow(nil)
            return ewc.archiveState
        } else {
            log.notice("Opening a new window for \(url.lastPathComponent)")
            return createAndShowArchiveWindow(url)
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
