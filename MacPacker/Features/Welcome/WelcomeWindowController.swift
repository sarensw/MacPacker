//
//  WelcomeWindowController.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 22.09.23.
//

import Foundation
import AppKit
import SwiftUI

@MainActor
class WelcomeWindowController {
    private var welcomeWindow: NSWindow? = nil
    private var welcomeWindowController: NSWindowController? = nil
    
    init() {
        // load the window
        welcomeWindow = NSWindow()
        welcomeWindow?.titlebarAppearsTransparent = true
        welcomeWindow?.isMovableByWindowBackground = true
        welcomeWindow?.showsToolbarButton = true
        welcomeWindow?.styleMask = [.titled, .closable]
        welcomeWindow?.setContentSize(NSSize(width: 640, height: 500))
        welcomeWindow?.center()
        
        let rootView = WelcomeView()
        let contentView = NSHostingView(rootView: rootView)
        contentView.autoresizingMask = [.width, .height]
        welcomeWindow?.contentView = contentView
        
        welcomeWindowController = NSWindowController(window: welcomeWindow)
    }
    
    func show() {
        welcomeWindow?.makeKeyAndOrderFront(self)
        welcomeWindowController?.showWindow(self)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
