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
    private var extractionProgressWindowController: ExtractionProgressWindowController? = nil
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
        // This is where you can also pass an updater delegate if you need one.
        // `-DisableUpdateChecks YES` suppresses the automatic check — useful for
        // scripted/automated launches (CI, screenshots) where a check dialog
        // would interrupt.
        let startUpdater = !Self.isRunningInPreview && !LaunchParameters.disableUpdateChecks
        updaterController = SPUStandardUpdaterController(
            startingUpdater: startUpdater,
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
                handler = AppUrlOpenHandler(catalog: appState.catalog)
            case .extractFiles:
//                handler = AppUrlExtractFilesHandler()
                break
            case .extractHere:
                handler = AppUrlExtractHereHandler(catalog: appState.catalog, engineSelector: appState.engineSelector)
            case .extractToFolder:
                handler = AppUrlExtractToFolderHandler(catalog: appState.catalog, engineSelector: appState.engineSelector)
            case .compress:
                handler = AppUrlCompressHandler(catalog: appState.catalog, engineSelector: appState.engineSelector)
            case .addToArchive:
                handler = AppUrlAddToArchiveHandler()
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

        // the terminate-time cleanup never runs when the app crashes or is
        // killed — clear stale extraction caches from previous runs here too
        CacheCleaner().clean()

        archiveWindowManager = ArchiveWindowManager(appState: appState)
        extractionProgressWindowController = ExtractionProgressWindowController(center: .shared)

        // When launched to open a specific archive (launch parameters) — or to
        // show the debug extraction preview — MacPacker shows that one window
        // instead of the empty launch window and the welcome screen.
        let opensArchive = LaunchParameters.opensArchive
#if DEBUG
        let showsExtractionDemo = ExtractionDemo.isRequested
#else
        let showsExtractionDemo = false
#endif
        let launchedToOpenSomething = opensArchive || showsExtractionDemo

        // make sure that at least one window will be shown even if it is empty
        if !launchedToOpenSomething {
            log.notice("Opening launch window (pending open urls: \(pendingOpenURLs.count))")
            archiveWindowManager?.openLaunchArchiveWindow()
        }

        // Launch parameters: open the requested archive and (optionally)
        // navigate to a path / select an item inside it.
        if let archiveWindowManager {
            LaunchParameters.applyIfNeeded(windowManager: archiveWindowManager)
        }

        // replay any open urls that arrived before the window manager existed
        if !pendingOpenURLs.isEmpty {
            let queued = pendingOpenURLs
            pendingOpenURLs.removeAll()
            log.notice("Replaying \(queued.count) queued open url(s)")
            application(NSApp, open: queued)
        }

        // opens the welcome window
        if !launchedToOpenSomething,
           welcomeScreenShownInVersion != Bundle.main.appVersionLong || Bundle.main.appVersionLong.contains("0.0.0-dev") {
            log.notice("Showing welcome window")
            WelcomeWindowController().show()
            welcomeScreenShownInVersion = Bundle.main.appVersionLong
        }
        log.notice("applicationDidFinishLaunching done")

#if DEBUG
        // Debug-only end-to-end hook: MACPACKER_DEBUG_EXTRACT="<archive>|<destDir>"
        // opens the archive headless and extracts it fully — lets the
        // extraction progress window be exercised without UI scripting.
        if let spec = ProcessInfo.processInfo.environment["MACPACKER_DEBUG_EXTRACT"] {
            let parts = spec.split(separator: "|").map(String.init)
            if parts.count == 2 {
                let archiveURL = URL(fileURLWithPath: parts[0])
                let destURL = URL(fileURLWithPath: parts[1], isDirectory: true)
                // MACPACKER_DEBUG_EXTRACT_ITEMS=1 exercises the item flow
                // (temp dir + move) instead of the full-archive flow
                let asItems = ProcessInfo.processInfo.environment["MACPACKER_DEBUG_EXTRACT_ITEMS"] != nil
                log.notice("DEBUG extract hook starting", context: ["archive": archiveURL.path, "dest": destURL.path, "asItems": "\(asItems)"])
                let state = ArchiveState(catalog: appState.catalog, engineSelector: appState.engineSelector)
                state.folderAccessProvider = { await FolderAccessStore.shared.ensureAccess(forFileIn: $0) }
                Task {
                    state.open(url: archiveURL)
                    try? await state.openTask?.value
                    if asItems {
                        let items = state.root?.children?.compactMap { state.entries[$0] } ?? []
                        state.extract(items: items, to: destURL)
                    } else {
                        state.extract(to: destURL)
                    }
                }
            }
        }

        // Debug-only end-to-end hook: MACPACKER_DEBUG_ZIPDELETE="<archive>|<entryName>"
        // opens the archive headless, removes the first entry with that name
        // and saves in place — the zip edit path without UI scripting.
        if let spec = ProcessInfo.processInfo.environment["MACPACKER_DEBUG_ZIPDELETE"] {
            let parts = spec.split(separator: "|").map(String.init)
            if parts.count == 2 {
                let archiveURL = URL(fileURLWithPath: parts[0])
                let entryName = parts[1]
                log.notice("DEBUG zip-delete hook starting", context: ["archive": archiveURL.path, "entry": entryName])
                let state = ArchiveState(catalog: appState.catalog, engineSelector: appState.engineSelector)
                Task {
                    state.open(url: archiveURL)
                    try? await state.openTask?.value
                    if let item = state.entries.values.first(where: { $0.name == entryName }) {
                        state.remove(items: [item])
                        await state.save()?.value
                        log.notice("DEBUG zip-delete hook done", context: ["error": state.error ?? "none"])
                    } else {
                        log.error("DEBUG zip-delete hook: entry not found", context: ["entry": entryName])
                    }
                }
            }
        }

        // Debug-only extraction preview: -ExtractDemo shows the extraction
        // window with mock progress so that window can be screenshotted in a
        // known state without running a real extraction.
        ExtractionDemo.applyIfRequested()
#endif
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

    /// Asked for in #119: don't let the app quit silently while an
    /// extraction is running.
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
#if DEBUG
        // The extraction demo keeps a job "active" on purpose; don't let the
        // quit-guard alert block the relaunches that drive its screenshots.
        if ExtractionDemo.isRequested { return .terminateNow }
#endif
        guard ExtractionProgressCenter.shared.hasActiveJobs else {
            return .terminateNow
        }

        log.notice("Quit requested while extraction is running — asking user")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "An extraction is still in progress", comment: "Title of the alert shown when the user quits while an extraction is running.")
        alert.informativeText = String(localized: "Quitting now stops the extraction and may leave incomplete files at the destination.", comment: "Body of the alert shown when the user quits while an extraction is running.")
        alert.addButton(withTitle: String(localized: "Cancel", comment: "Alert button that keeps the app running so the extraction can finish."))
        alert.addButton(withTitle: String(localized: "Quit Anyway", comment: "Alert button that quits the app even though an extraction is running."))

        if alert.runModal() == .alertFirstButtonReturn {
            log.notice("Quit cancelled — extraction continues")
            return .terminateCancel
        }
        log.notice("Quit forced during extraction")
        return .terminateNow
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

    func openCreateArchiveWindow() {
        self.archiveWindowManager?.openCreateArchiveWindow()
    }
}
