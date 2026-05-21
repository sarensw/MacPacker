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
        let rootView = WelcomeView()
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.layoutSubtreeIfNeeded()
        
        let fittingSize = hostingView.fittingSize
        
        // load the window
        welcomeWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: fittingSize.height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        welcomeWindow?.titlebarAppearsTransparent = true
        welcomeWindow?.isMovableByWindowBackground = true
        welcomeWindow?.showsToolbarButton = true
        welcomeWindow?.styleMask = [.titled, .closable, .fullSizeContentView]
        welcomeWindow?.setContentSize(NSSize(width: 640, height: 500))
        welcomeWindow?.center()
        welcomeWindow?.contentView = hostingView
        
        let fixedSize = NSSize(width: 800, height: fittingSize.height)
        
        welcomeWindow?.minSize = fixedSize
        welcomeWindow?.maxSize = fixedSize
        welcomeWindow?.setContentSize(fixedSize)
        
        welcomeWindowController = NSWindowController(window: welcomeWindow)
    }
    
    func show() {
        welcomeWindow?.makeKeyAndOrderFront(self)
        welcomeWindowController?.showWindow(self)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
