//
//  PasswordWindow.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 25.03.26.
//

import AppKit
import Core
import SwiftUI

class PasswordWindowController: NSWindowController, NSWindowDelegate {
    let archiveState: ArchiveState
    
    init(archiveState: ArchiveState) {
        self.archiveState = archiveState
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 150),
            styleMask: [.closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        let view = PasswordView()
        
        window.contentView = NSHostingView(rootView: view)
        
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coer:) has not been implemented")
    }
}
