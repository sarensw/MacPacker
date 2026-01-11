//
//  AckWindowController.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 11.01.26.
//

import Foundation
import AppKit
import SwiftUI

@MainActor
class AckWindowController {
    private var ackWindow: NSWindow? = nil
    private var ackWindowController: NSWindowController? = nil
    
    init() {
        // load the window
        ackWindow = NSWindow()
        ackWindow?.titlebarAppearsTransparent = true
        ackWindow?.isMovableByWindowBackground = true
        ackWindow?.showsToolbarButton = true
        ackWindow?.styleMask = [.titled, .closable]
        ackWindow?.setContentSize(NSSize(width: 640, height: 500))
        ackWindow?.center()
        
        let rootView = AcknowledgementsView()
        let contentView = NSHostingView(rootView: rootView)
        contentView.autoresizingMask = [.width, .height]
        ackWindow?.contentView = contentView
        
        ackWindowController = NSWindowController(window: ackWindow)
    }
    
    func show() {
        ackWindow?.makeKeyAndOrderFront(self)
        ackWindowController?.showWindow(self)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
