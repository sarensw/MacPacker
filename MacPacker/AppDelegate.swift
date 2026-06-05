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
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "lifecycle")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @AppStorage("welcomeScreenShownInVersion") private var welcomeScreenShownInVersion = "0.0"
    @AppStorage("updateBetaChannelOn") var updateBetaChannelOn: Bool = false
    @AppStorage("checkForUpdates") var checkForUpdates: SettingUpdateCheck = .automatically
    @AppStorage(Keys.quitOnLastWindowClosed) var quitOnLastWindowClosed: Bool = false
    private var archiveWindowManager: ArchiveWindowManager? = nil
    private var pendingOpenURLs: [URL] = []
    
    private static var isRunningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
    #if !STORE
    private let updaterDelegate = UpdaterDelegate()
    let updaterController: SPUStandardUpdaterController
    #endif

    let appState: AppState
    
    override init() {
        log.notice("AppDelegate.init starting")
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
        log.notice("AppDelegate.init complete — appState ready")
    }

    public func applicationWillFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningInPreview else { return }
        log.notice("applicationWillFinishLaunching")
    }
    
    public func application(_ application: NSApplication, open urls: [URL]) {
        log.notice("application(open:) received \(urls.count) url(s)", context: ["first": urls.first?.lastPathComponent ?? "-", "windowManagerReady": "\(archiveWindowManager != nil)"])

        // On a cold start the open event can arrive before applicationDidFinishLaunching
        // has created the window manager. Queue the urls and replay them once we're ready.
        guard archiveWindowManager != nil else {
            log.notice("Window manager not ready yet — queuing \(urls.count) url(s) until launch finishes")
            pendingOpenURLs.append(contentsOf: urls)
            return
        }

        // first check if this is an app url, and handle it accordingly
        if let url = urls.first,
           let appUrl: AppUrl = UrlParser().parse(appUrl: url) {
            log.notice("Routing Finder app-url action '\(appUrl.action.rawValue)' for \(appUrl.files.count) file(s)")
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

            guard let handler else {
                log.error("No handler available for action '\(appUrl.action.rawValue)'")
                return
            }
            guard let archiveWindowManager else {
                log.error("Archive window manager not ready; dropping action '\(appUrl.action.rawValue)'")
                return
            }

            // we have all the url info, start the handlers now
            handler.handle(appUrl: appUrl, archiveWindowManager: archiveWindowManager)

            // no need to move further here as it was an app url
            return
        }

        // it is not an app url, therefore the assumption is that the app
        // was opened via Finder > right click > Open with...
        for url in urls {
            log.notice("Open-with: opening \(url.lastPathComponent)")
            archiveWindowManager?.openArchiveWindow(for: url)
        }
    }
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningInPreview else { return }
        log.notice("applicationDidFinishLaunching — creating window manager")

        archiveWindowManager = ArchiveWindowManager(appState: appState)

        // make sure that at least one window will be shown
        // even if it is empty
        log.notice("Opening launch window (pending open urls: \(pendingOpenURLs.count))")
        archiveWindowManager?.openLaunchArchiveWindow()

        // replay any open urls that arrived before the window manager existed
        if !pendingOpenURLs.isEmpty {
            let queued = pendingOpenURLs
            pendingOpenURLs.removeAll()
            log.notice("Replaying \(queued.count) queued open url(s)")
            application(NSApp, open: queued)
        }

        // opens the welcome window
        if welcomeScreenShownInVersion != Bundle.main.appVersionLong || Bundle.main.appVersionLong.contains("0.0.0-dev") {
            log.notice("Showing welcome window")
            WelcomeWindowController().show()
            welcomeScreenShownInVersion = Bundle.main.appVersionLong
        }
        log.notice("applicationDidFinishLaunching done")
    }
    
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !Self.isRunningInPreview else { return true }
        log.notice("applicationShouldHandleReopen (hasVisibleWindows: \(hasVisibleWindows))")
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
        log.notice("applicationWillTerminate — cleaning cache")
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
