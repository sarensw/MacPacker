//
//  AppDelegate.swift
//  Modules
//
//  Created by Stephan Arenswald on 02.12.25.
//

import AppKit
import Core
import Foundation
import SwiftUI
import TailBeatKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @AppStorage("welcomeScreenShownInVersion") private var welcomeScreenShownInVersion = "0.0"
    private var openWithUrls: [URL] = []
    private var archiveWindowManager: ArchiveWindowManager? = nil
    
    public let archiveEngineConfigStore: ArchiveEngineConfigStore = ArchiveEngineConfigStore()
    
    override init() {
        super.init()
        archiveWindowManager = ArchiveWindowManager(appDelegate: self)
        TailBeat.start()
    }
    
    public func application(_ application: NSApplication, open urls: [URL]) {
        Logger.log("open \(urls)")

        // first check if this is an app url, and handle it accordingly
        if let url = urls.first,
           let appUrl: AppUrl = UrlParser().parse(appUrl: url) {
            var handler: AppUrlHandler?

            // we will be here if this is a valid app url
            // (url starting with app.macpacker:// scheme)
            switch appUrl.action {
            case .open:
                handler = AppUrlOpenHandler()
            case .extractFiles:
//                handler = AppUrlExtractFilesHandler()
                break
            case .extractHere:
                handler = AppUrlExtractHereHandler()
            case .extractToFolder:
                handler = AppUrlExtractToFolderHandler()
            }
            
            // we have all the url info, start the handlers now
            handler!.handle(
                appUrl: appUrl,
                archiveWindowManager: archiveWindowManager!
            )
            
            // no need to move further here as it was an app url
            return
        }
        
        // it is not an app url, therefore the assumption is that the app
        // was opened via Finder > right click > Open with...
        for url in urls {
            Logger.log("want to open for \(url)")
            archiveWindowManager?.openArchiveWindow(for: url)
        }
    }
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.log("finish launching")
        
        // make sure that at least one window will be shown
        // even if it is empty
        archiveWindowManager?.openLaunchArchiveWindow()
        
        if let appVersion = Version(Bundle.main.appVersionLong),
           let welcomeVersion = Version(welcomeScreenShownInVersion) {
            if appVersion > welcomeVersion {
                Logger.debug("Higher app version detected, showing welcome screen")
                WelcomeWindowController().show()
                welcomeScreenShownInVersion = Bundle.main.appVersionLong
            }
        }
        
        #if !DEBUG
        if FIFinderSyncController.isExtensionEnabled == false {
            FIFinderSyncController.showExtensionManagementInterface()
        }
        #endif
    }
    
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            archiveWindowManager?.openArchiveWindow()
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        CacheCleaner().clean()
    }
    
    public func openAboutWindow() {
        
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.titlebarAppearsTransparent = true
        window.center()
        window.isRestorable = false
        
        let contentView = AboutView()
        
        window.contentView = NSHostingView(rootView: contentView)
        
        // show the window
        window.makeKeyAndOrderFront(nil)
    }
    
    public func openArchiveUsingOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .data
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.begin() { response in
            if response == .OK, let url = panel.url {
                self.archiveWindowManager?.openArchiveWindow(for: url)
            }
        }
    }
}
