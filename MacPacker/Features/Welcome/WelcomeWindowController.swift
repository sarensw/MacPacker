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
        let targetWidth: CGFloat = 800

        let hostingView = NSHostingView(rootView: WelcomeView().frame(width: targetWidth))
        hostingView.frame = NSRect(x: 0, y: 0, width: targetWidth, height: 0)
        hostingView.layoutSubtreeIfNeeded()
        let contentSize = NSSize(width: targetWidth, height: ceil(hostingView.fittingSize.height))

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.showsToolbarButton = true
        window.contentView = hostingView
        window.minSize = contentSize
        window.maxSize = contentSize
        window.center()

        self.welcomeWindow = window
        self.welcomeWindowController = NSWindowController(window: window)
    }
    
    func show() {
        welcomeWindow?.makeKeyAndOrderFront(self)
        welcomeWindowController?.showWindow(self)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
