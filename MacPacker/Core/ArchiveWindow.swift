//
//  ArchiveWindow.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 21.09.25.
//

import AppKit

class ArchiveWindowDelegate: NSObject, NSWindowDelegate {
    var willClose: (() -> Void)?
    
    func windowWillClose(_ notification: Notification) {
        if let willClose { willClose() }
    }
}

class ArchiveWindow: NSWindow {
    var archiveState: ArchiveState
    
    init(archiveState: ArchiveState) {
        self.archiveState = archiveState
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
    }
    
    required init?(coder: NSCoder) {
        self.archiveState = ArchiveState()
        fatalError("init(coder:) has not been implemented")
    }
}
