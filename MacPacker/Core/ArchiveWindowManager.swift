//
//  ArchiveWindowManager.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 24.09.25.
//

import AppKit
import Foundation
import SwiftUI

class ArchiveWindowManager {
    private var windows: [ArchiveWindow] = []
    private let appDelegate: AppDelegate
    
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
    }
    
    func closeAll() {
        windows.forEach { window in
            window.close()
        }
        windows.removeAll()
    }
    
    func openArchiveWindow() {
        openArchiveWindow(for: nil)
    }
    
    func openArchiveWindow(for url: URL?) {
        Logger.log("creating new window for \(String(describing: url))")
        
        // first check if there is a window that can be reused
        if let url {
            for window in windows {
                // two cases here
                //
                // 1. There is a window where this exact archive is loaded
                //    already. In this case bring that window to the front,
                //    make it main and key
                // 2. There is a window that has no archive loaded, and
                //    where the user did not start to create a new archive.
                //    In this case .archive == nil
                if let archive = window.archiveState.archive {
                    // 1st case
                    if archive.url == url {
                        window.makeKeyAndOrderFront(nil)
                        return
                    }
                } else {
                    // 2nd case
                    let archiveState = window.archiveState
                    archiveState.loadUrl(url)
                    
                    // stop here, we have just loaded the url into an
                    // empty window
                    return
                }
            }
        }
        
        // every window has an archive state which defines both empty
        // (not yet loaded archives) or loaded archives
        let archiveState = ArchiveState()
        if let url {
            archiveState.loadUrl(url)
        }
        
        // create the window and place the archive state in it to check
        // later if there is a window without archive that could be used
        // to open a new archive
        let delegate = ArchiveWindowDelegate()
        delegate.willClose = { [weak self] in
            Logger.log("window closed")
            if let self {
                Logger.log(String(describing: self.windows.count))
                self.windows.removeAll { $0 === $0 }
            }
        }
        let window = ArchiveWindow(archiveState: archiveState)
        window.isRestorable = false
        window.center()
        window.delegate = delegate
        windows.append(window)
        
        // show the content view
        let contentView = ContentView()
            .environment(AppState.shared)
            .environmentObject(appDelegate)
            .environmentObject(archiveState)
        
        window.contentView = NSHostingView(rootView: contentView)
        
        // show the window
        window.makeKeyAndOrderFront(nil)
    }
}
