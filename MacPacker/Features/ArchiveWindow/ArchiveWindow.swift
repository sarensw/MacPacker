//
//  ArchiveWindow.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 21.09.25.
//

import AppKit
import Combine
import Core
import SwiftUI

class ArchiveWindowController: NSWindowController, NSWindowDelegate {
    let archiveState: ArchiveState

    let contentService: ArchiveContentService = ArchiveContentService()

    var willCloseHandler: (() -> Void)?
    var didBecomeMain: (() -> Void)?

    private var cancellables = Set<AnyCancellable>()
    
    init(
        archiveState: ArchiveState,
        appState: AppState,
        dropCompressor: DropCompressor,
        openQuickCompressWindow: @escaping @MainActor () -> Void,
        openArchiveInNewWindow: @escaping @MainActor (URL) -> Void,
        cascadeFrom: NSWindow? = nil
    ) {
        self.archiveState = archiveState

        let window = ArchiveWindow()
        window.isRestorable = false
        let didRestoreFrame = window.setFrameAutosaveName("ArchiveWindow")
        if let cascadeFrom {
            let nextPoint = cascadeFrom.cascadeTopLeft(from: NSPoint(x: cascadeFrom.frame.minX, y: cascadeFrom.frame.maxY))
            window.setFrameTopLeftPoint(nextPoint)
        } else if didRestoreFrame {
            let onScreen = NSScreen.screens.contains { screen in
                let intersection = screen.visibleFrame.intersection(window.frame)
                let minWidth = min(window.frame.width * 0.5, 300)
                let minHeight = min(window.frame.height * 0.5, 200)
                return !intersection.isNull && intersection.width >= minWidth && intersection.height >= minHeight
            }
            if !onScreen || window.frame.origin == .zero {
                window.center()
            }
        } else {
            window.center()
        }
        super.init(window: window)

        window.delegate = self

        window.toolbarStyle = .unified

        // show the content view
        let contentView = ContentView()
            .environmentObject(appState)
            .environmentObject(archiveState)
            .environmentObject(dropCompressor)
            .environment(\.openArchiveInNewWindow, openArchiveInNewWindow)
            .environment(\.openQuickCompressWindow, openQuickCompressWindow)

        window.contentView = NSHostingView(rootView: contentView)

        // native unsaved-changes affordance: the close button shows a dot while
        // there are pending edits (mirrors NSDocument's isDocumentEdited)
        archiveState.$diff
            .map { !$0.isEmpty }
            .removeDuplicates()
            .sink { [weak window] edited in window?.isDocumentEdited = edited }
            .store(in: &cancellables)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// SwiftUI fills the toolbar after the hosting view is installed, so the
    /// search field does not exist yet at init. This is the first moment it
    /// reliably does; the call is idempotent and cheap.
    func windowDidUpdate(_ notification: Notification) {
        (notification.object as? NSWindow)?.publishAccessibilityIdentifiers()
    }

    /// Closing a window with unsaved edits asks to save first, like a document
    /// (this is a plain NSWindow, not an NSDocument, so it's wired by hand).
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard archiveState.canBeEdited,
              archiveState.hasPendingChanges,
              !archiveState.isSaving else { return true }

        let name = archiveState.name ?? String(localized: "the archive", comment: "Fallback name in the save-on-close prompt when the archive has no file name yet")
        let alert = NSAlert()
        alert.messageText = String(localized: "Do you want to save the changes you made to “\(name)”?", comment: "Title of the prompt shown when closing an archive window with unsaved changes")
        alert.informativeText = String(localized: "Your changes will be lost if you don’t save them.", comment: "Explanation in the save-on-close prompt")
        alert.addButton(withTitle: String(localized: "Save", comment: "Button in the save-on-close prompt that saves the archive"))
        alert.addButton(withTitle: String(localized: "Cancel", comment: "Button in the save-on-close prompt that keeps the window open"))
        alert.addButton(withTitle: String(localized: "Don’t Save", comment: "Button in the save-on-close prompt that discards the changes"))
        alert.buttons[1].keyEquivalent = "\u{1b}"                                  // Esc = Cancel
        alert.buttons[2].keyEquivalent = "d"; alert.buttons[2].keyEquivalentModifierMask = .command  // ⌘D = Don't Save

        alert.beginSheetModal(for: sender) { [weak self] response in
            switch response {
            case .alertFirstButtonReturn: self?.saveThenClose(window: sender) // Save
            case .alertThirdButtonReturn: sender.close()                      // Don't Save
            default: break                                                     // Cancel
            }
        }
        return false
    }

    /// Saves the pending changes and closes the window once the write finishes.
    /// A cancelled save panel (new archive) or a failed write keeps it open.
    private func saveThenClose(window: NSWindow) {
        let closeWhenSaved: (Task<Void, Never>?) -> Void = { [weak self] task in
            guard let self, let task else { return }
            Task { @MainActor in
                await task.value
                if !self.archiveState.hasPendingChanges { window.close() }
            }
        }
        if archiveState.url == nil {
            ArchiveSavePanel.runAndSave(state: archiveState, window: window, onSave: closeWhenSaved)
        } else {
            closeWhenSaved(archiveState.save())
        }
    }

    func windowWillClose(_ notification: Notification) {
        archiveState.clean()
        willCloseHandler?()
    }
}

class ArchiveWindow: NSWindow {
    /// SwiftUI builds the NSToolbar for `.toolbar {}` itself, leaves
    /// `autosavesConfiguration` off, and its generated identifier isn't ours to
    /// set, so "Icon and Text" is remembered by hand (issue #141).
    private var displayModeObserver: NSKeyValueObservation?

    override var toolbar: NSToolbar? {
        didSet {
            displayModeObserver = nil
            guard let toolbar else { return }

            let saved = UserDefaults.standard.integer(forKey: Keys.toolbarDisplayMode)
            if saved > 0, let mode = NSToolbar.DisplayMode(rawValue: UInt(saved)) {
                toolbar.displayMode = mode
            }

            // the change dictionary is read off the toolbar, not `change.newValue`:
            // NSToolbar posts a correct KVO notification, but Swift can't bridge the
            // boxed NSNumber back to DisplayMode, so newValue always arrives nil
            displayModeObserver = toolbar.observe(\.displayMode) { toolbar, _ in
                // KVO is delivered synchronously on whichever thread set the
                // property, and only AppKit/SwiftUI set this one — always main
                MainActor.assumeIsolated {
                    let mode = toolbar.displayMode
                    // .default never comes from the context menu — ignoring it stops a
                    // SwiftUI toolbar rebuild from wiping the user's choice
                    guard mode != .default else { return }
                    UserDefaults.standard.set(mode.rawValue, forKey: Keys.toolbarDisplayMode)
                }
            }
        }
    }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
    }
}

/// Lets a window's content open a *different* archive in a new window (the
/// ⌥-drag-to-open gesture) without holding — or cycling with — the window manager.
/// `ArchiveWindowController` injects a weakly-captured closure from the manager.
private struct OpenArchiveInNewWindowKey: EnvironmentKey {
    static let defaultValue: @MainActor (URL) -> Void = { _ in }
}

extension EnvironmentValues {
    var openArchiveInNewWindow: @MainActor (URL) -> Void {
        get { self[OpenArchiveInNewWindowKey.self] }
        set { self[OpenArchiveInNewWindowKey.self] = newValue }
    }
}

/// Opens the floating quick-compress window. An action, not state, so it travels
/// as a closure rather than as an object a view has to hold.
private struct OpenQuickCompressWindowKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = { }
}

extension EnvironmentValues {
    var openQuickCompressWindow: @MainActor () -> Void {
        get { self[OpenQuickCompressWindowKey.self] }
        set { self[OpenQuickCompressWindowKey.self] = newValue }
    }
}
