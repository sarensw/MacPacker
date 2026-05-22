//
//  AppDelegate.swift
//  Modules
//
//  Created by Stephan Arenswald on 02.12.25.
//

import AppKit
import Core
import Foundation
#if !STORE
import Sparkle
#endif
import SwiftUI
import TailBeatKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @AppStorage("welcomeScreenShownInVersion") private var welcomeScreenShownInVersion = "0.0"
    @AppStorage("updateBetaChannelOn") var updateBetaChannelOn: Bool = false
    @AppStorage("checkForUpdates") var checkForUpdates: SettingUpdateCheck = .automatically
    @AppStorage(Keys.quitOnLastWindowClosed) var quitOnLastWindowClosed: Bool = false
    private var archiveWindowManager: ArchiveWindowManager? = nil
    
    private static var isRunningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
    #if !STORE
    private let updaterDelegate = UpdaterDelegate()
    let updaterController: SPUStandardUpdaterController
    #endif

    let appState: AppState
    
    override init() {
        #if !STORE
        // If you want to start the updater manually, pass false to startingUpdater and call .startUpdater() later
        // This is where you can also pass an updater delegate if you need one
        updaterController = SPUStandardUpdaterController(
            startingUpdater: !Self.isRunningInPreview,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )
        appState = AppState(updaterController: updaterController)
        #else
        appState = AppState()
        #endif
        
        super.init()
        if !Self.isRunningInPreview {
        TailBeat.start()
        }
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
                handler = AppUrlExtractHereHandler(catalog: appState.catalog, engineSelector: appState.engineSelector)
            case .extractToFolder:
                handler = AppUrlExtractToFolderHandler(catalog: appState.catalog, engineSelector: appState.engineSelector)
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
        guard !Self.isRunningInPreview else { return }
        Logger.log("finish launching")
        
        archiveWindowManager = ArchiveWindowManager(appState: appState)
        
        // make sure that at least one window will be shown
        // even if it is empty
        archiveWindowManager?.openLaunchArchiveWindow()
        
        // opens the welcome window
        if welcomeScreenShownInVersion != Bundle.main.appVersionLong || Bundle.main.appVersionLong.contains("0.0.0-dev") {
            WelcomeWindowController().show()
            welcomeScreenShownInVersion = Bundle.main.appVersionLong
        }
    }
    
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !Self.isRunningInPreview else { return true }
        if !hasVisibleWindows {
            archiveWindowManager?.openArchiveWindow()
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }
    
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if quitOnLastWindowClosed {
            return true
        }
        return false
    }

    public func applicationWillTerminate(_ notification: Notification) {
        guard !Self.isRunningInPreview else { return }
        CacheCleaner().clean()
    }
    
    func openArchiveUsingOpenPanel() {
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
    
    func openNewArchiveWindow() {
        self.archiveWindowManager?.openNewArchiveWindow()
    }
}
