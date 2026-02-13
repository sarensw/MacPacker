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
    let appDelegate: AppDelegate
    
    let contentService: ArchiveContentService = ArchiveContentService()
    
    var willCloseHandler: (() -> Void)?
    
    init(archiveState: ArchiveState, appDelegate: AppDelegate) {
        self.archiveState = archiveState
        self.appDelegate = appDelegate
        
        let window = ArchiveWindow()
        window.isRestorable = false
        window.center()
        super.init(window: window)
        
        window.delegate = self
        
        if #unavailable(macOS 14) {
            // we have to use a classic toolbar for macOS 13 based on NSToolbar
            // > no need for an else here as SwiftUIs .toolbar() loads the
            //   toolbar in ContentView
            let toolbar = NSToolbar(identifier: "ArchiveWindowToolbar")
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            window.toolbar = toolbar
            
            window.title = Bundle.main.displayName
        }
        
        window.toolbarStyle = .unified
        
        // show the content view
        let contentView = ContentView()
            .environmentObject(appDelegate)
            .environmentObject(archiveState)
        
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
