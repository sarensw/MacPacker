//
//  ArchiveWindowManager.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 24.09.25.
//

import AppKit
import Foundation
import MacPackerCore
import SwiftUI

class ArchiveWindowManager {
    private var windowControllers: [ArchiveWindowController] = []
    private let appDelegate: AppDelegate
    
    /// Default constructor
    /// - Parameter appDelegate: app delegate for handover to the archive windows
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
    }
    
    /// Creates a new archive window and loads the archive from the given url if available
    /// - Parameter url: url of the archive
    fileprivate func createAndShowArchiveWindow(_ url: URL?) {
        // every window has an archive state which defines both empty
        // (not yet loaded archives) or loaded archives
        let archiveState = ArchiveState()
        if let url {
            archiveState.load(from: url)
        }
        
        // create the window and place the archive state in it to check
        // later if there is a window without archive that could be used
        // to open a new archive
        let archiveWindowController = ArchiveWindowController(
            archiveState: archiveState,
            appDelegate: appDelegate
        )
        windowControllers.append(archiveWindowController)
        archiveWindowController.willCloseHandler = { [weak self] in
            self?.windowControllers.removeAll { $0 === archiveWindowController }
        }
        archiveWindowController.showWindow(nil)
    }
    
    /// During launch two things might happen. Either the app is launched with a url (e.g. via the Open With... menu
    /// or without. The order of `application(_:open:)` and `applicationDidFinishLaunching` is not
    /// guaranteed. That's why `openLaunchArchiveWindow` is only called once when the app launches
    /// and only creates an empty window in case the app was not launched with a url.
    func openLaunchArchiveWindow() {
        if windowControllers.isEmpty {
            createAndShowArchiveWindow(nil)
        }
    }
    
    /// Creates a new empty window, or shows an existing empty window where no archive is loaded or created yet
    func openArchiveWindow() {
        if let ewc = windowControllers.first(where: { $0.archiveState.archive == nil }) {
            ewc.showWindow(nil)
        } else {
            createAndShowArchiveWindow(nil)
        }
    }
    
    /// Opens the given url into an archive window with three options.
    ///
    /// 1. archive loaded already: Open that existing window (don't reload the archive again)
    /// 2. archive not loaded yet: If there is a window without an archive, reuse this window, otherwise open a new one
    /// 3. no `url` given: Open a new window if there is no empty window available
    /// - Parameter url: url to open (if `nil`, just create an empty window)
    func openArchiveWindow(for url: URL) {
        Logger.log("creating new window for \(String(describing: url))")
        
        if let wc = windowControllers.first(where: { $0.archiveState.archive?.url == url }) {
            // Case 1: archive already loaded > bring window to front
            wc.showWindow(nil)
        } else if let ewc = windowControllers.first(where: { $0.archiveState.archive == nil }) {
            // Case 2: archive not loaded yet, but empty window available > load archive in empty
            // and bring window to front
            ewc.archiveState.load(from: url)
            ewc.showWindow(nil)
        } else {
            // Case 3: archive not loaded yet, no empty window available > create new window and
            // load archive in it
            createAndShowArchiveWindow(url)
        }
    }
}
