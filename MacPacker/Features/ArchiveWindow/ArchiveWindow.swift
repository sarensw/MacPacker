//
//  ArchiveWindow.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 21.09.25.
//

import AppKit
import Core
import SwiftUI

class ArchiveWindowController: NSWindowController, NSWindowDelegate {
    let archiveState: ArchiveState
    
    let contentService: ArchiveContentService = ArchiveContentService()
    
    var willCloseHandler: (() -> Void)?
    var didBecomeMain: (() -> Void)?
    
    init(
        archiveState: ArchiveState,
        appState: AppState,
        openArchiveInNewWindow: @escaping @MainActor (URL) -> Void
    ) {
        self.archiveState = archiveState

        let window = ArchiveWindow()
        window.isRestorable = false
        window.center()
        super.init(window: window)

        window.delegate = self

        window.toolbarStyle = .unified

        // show the content view
        let contentView = ContentView()
            .environmentObject(appState)
            .environmentObject(archiveState)
            .environment(\.openArchiveInNewWindow, openArchiveInNewWindow)

        window.contentView = NSHostingView(rootView: contentView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func windowWillClose(_ notification: Notification) {
        archiveState.clean()
        willCloseHandler?()
    }
}

class ArchiveWindow: NSWindow {
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
