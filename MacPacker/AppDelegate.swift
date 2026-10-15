//
//  AppDelegate.swift
//  Modules
//
//  Created by Stephan Arenswald on 02.12.25.
//

import AppKit
import Core
import FinderMenu
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
    private var dropMenuBarItem: DropMenuBarItem? = nil
    /// The one compressor behind every "drop files to compress" surface — the
    /// quick-compress window and the start page's compress column. Shared so the
    /// settings apply wherever you drop and a job shows up in both.
    private var dropCompressor: DropCompressor? = nil
    private var dropWindowController: DropWindowController? = nil
    private var pendingOpenURLs: [URL] = []
    /// What the app was launched for: it decides the launch windows, and
    /// whether the app quits again when a Finder action is done.
    private var launch = Launch()

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
        // The updater is not started here but once the app is in use as an
        // app: see `startUpdateChecksIfInUse`.
        // This is where you can also pass an updater delegate if you need one.
        // `-DisableUpdateChecks YES` suppresses the automatic check — useful for
        // scripted/automated launches (CI, screenshots) where a check dialog
        // would interrupt.
        let allowsUpdateChecks = !Self.isRunningInPreview && !LaunchParameters.disableUpdateChecks
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )
        appState = AppState(updaterController: updaterController, allowsUpdateChecks: allowsUpdateChecks)
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
        let appUrl: AppUrl? = urls.first.flatMap { UrlParser().parse(appUrl: $0) }

        // On a cold start this is what the launch was started for, so it
        // decides the launch windows. The welcome window goes on top of what
        // opens below.
        let showsLaunchWindows = launch.started(for: appUrl == nil ? .openWith : .finderExtension)
        if showsLaunchWindows {
            openLaunchWindow()
        }
        defer {
            if showsLaunchWindows {
                showWelcomeWindowIfDue()
            }
        }

        if let appUrl {
            log.notice("Routing Finder app-url action '\(appUrl.action.rawValue)' for \(appUrl.files.count) file(s)")
            var handler: AppUrlHandler?

            // we will be here if this is a valid app url
            // (url starting with app.macpacker:// scheme)
            switch appUrl.action {
            case .open:
                handler = AppUrlOpenHandler()
            case .extractHere:
                handler = AppUrlExtractHereHandler(catalog: appState.catalog, engineSelector: appState.engineSelector)
            case .extractToFolder:
                handler = AppUrlExtractToFolderHandler(catalog: appState.catalog, engineSelector: appState.engineSelector)
            case .compress:
                handler = AppUrlCompressHandler(catalog: appState.catalog, engineSelector: appState.engineSelector)
            case .addToArchive:
                handler = AppUrlAddToArchiveHandler()
            case .extractTo:
                handler = AppUrlExtractToChosenFolderHandler(catalog: appState.catalog, engineSelector: appState.engineSelector)
            case .compressEach:
                handler = AppUrlCompressEachHandler(catalog: appState.catalog, engineSelector: appState.engineSelector)
            case .compressContents:
                handler = AppUrlCompressContentsHandler(catalog: appState.catalog, engineSelector: appState.engineSelector)
            case .extractNextToArchive:
                handler = AppUrlExtractNextToArchiveHandler(catalog: appState.catalog, engineSelector: appState.engineSelector)
            }

            guard let handler else {
                log.error("No handler available for action '\(appUrl.action.rawValue)'")
                return
            }
            guard let archiveWindowManager else {
                log.error("Archive window manager not ready; dropping action '\(appUrl.action.rawValue)'")
                return
            }

            // We have all the url info, start the handlers now. The action
            // counts as under way until all of it is done, so that the app
            // does not quit in the middle of it: see
            // `applicationShouldTerminateAfterLastWindowClosed`.
            Task {
                await ExtractionProgressCenter.shared.run {
                    await handler.handle(appUrl: appUrl, archiveWindowManager: archiveWindowManager)
                }
                if finderLaunchIsOver {
                    log.notice("Launched for a Finder action, which is done — quitting")
                    NSApp.terminate(nil)
                }
            }

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

        // Built before the window manager: the archive windows are handed the
        // compressor and the way to open the quick-compress window, so their
        // content can reach both from the environment.
        let dropCompressor = DropCompressor(
            catalog: appState.catalog,
            engineSelector: appState.engineSelector,
            folderAccess: { await FolderAccessStore.shared.ensureAccess(forFileIn: $0) })
        // Quick Compress's settings, kept as they change: one set for the window
        // and the start page's format menu. A password lasts until the app quits.
        let quickCompressOptions = ArchiveSaveOptions(storage: .quickCompress)
        let dropWindowController = DropWindowController(compressor: dropCompressor, options: quickCompressOptions)
        self.dropCompressor = dropCompressor
        self.dropWindowController = dropWindowController

        archiveWindowManager = ArchiveWindowManager(
            appState: appState,
            dropCompressor: dropCompressor,
            quickCompressOptions: quickCompressOptions,
            openQuickCompressWindow: { dropWindowController.show() }
        )
        // from its first window on, the app is in use as an app
        archiveWindowManager?.onFirstWindowOpened = { [weak self] in self?.startUpdateChecksIfInUse() }
        extractionProgressWindowController = ExtractionProgressWindowController(center: .shared)

        // The window is cheap (the panel itself is built on first show); the menu
        // bar item installs itself only if the user switched it on.
        dropMenuBarItem = DropMenuBarItem(actions: .init(
            quickCompress: { dropWindowController.show() },
            openArchive: { [weak self] in self?.openArchiveUsingOpenPanel() },
            newWindow: { [weak self] in self?.openNewArchiveWindow() }
        ))
        if LaunchParameters.opensDropWindow {
            dropWindowController.show()
            // -AddFiles alongside -DropWindow means "compress these now", the
            // scripted equivalent of dropping them on the window.
            let files = LaunchParameters.filesToAdd
            if !files.isEmpty { dropWindowController.compress(files: files) }
        }

        // When launched to open a specific archive (launch parameters) — or to
        // show the debug extraction preview — MacPacker shows that one window
        // instead of the empty launch window and the welcome screen.
        let opensWindow = LaunchParameters.opensWindow
#if DEBUG
        let showsExtractionDemo = ExtractionDemo.isRequested
#else
        let showsExtractionDemo = false
#endif
        let launchedToOpenSomething = opensWindow || showsExtractionDemo

        // What the launch was started for decides whether it shows the launch
        // window and the welcome window. Launch parameters say so themselves,
        // and a launch that asked for the app itself comes with the "open
        // application" event. Any other launch is to open something: an
        // archive, or an action from Finder's menu, which must leave the
        // screen as it was (#279). That decides in `application(_:open:)`,
        // where it arrives, and it may still be on its way: AppKit hands it
        // over once it is done restoring windows, on one launch before this
        // point and on the next after it. Should a launch bring nothing to
        // open after all, it shows nothing either, until the app is opened:
        // see `applicationShouldHandleReopen`.
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        let startedAsApp = launchEvent?.eventClass == AEEventClass(kCoreEventClass)
            && launchEvent?.eventID == AEEventID(kAEOpenApplication)
        let showsLaunchWindows: Bool
        if launchedToOpenSomething {
            showsLaunchWindows = launch.started(for: .launchParameters)
        } else if startedAsApp {
            showsLaunchWindows = launch.started(for: .app)
        } else {
            showsLaunchWindows = false
            log.notice("Not launched for the app itself (pending open urls: \(pendingOpenURLs.count))")
        }

        // launch parameters do not always come with an archive window
        startUpdateChecksIfInUse()

        // make sure that at least one window will be shown even if it is empty
        if showsLaunchWindows {
            openLaunchWindow()
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
        if showsLaunchWindows {
            showWelcomeWindowIfDue()
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
                        state.extract(items: items, to: destURL, smart: Keys.smartExtractionEnabled())
                    } else {
                        state.extract(to: destURL, smart: Keys.smartExtractionEnabled())
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
    
    /// Starts the update checks once the app is in use as an app: opened as
    /// one, or with a window of its own by now. Not for a Finder action that
    /// started it, which is over in a moment.
    private func startUpdateChecksIfInUse() {
#if !STORE
        guard launch.checksForUpdates(usedAsApp: archiveWindowManager?.hasOpenedWindow ?? false) else { return }
        appState.startUpdateChecks()
#endif
    }

    private func openLaunchWindow() {
        log.notice("Opening launch window")
        archiveWindowManager?.openLaunchArchiveWindow()
    }

    private func showWelcomeWindowIfDue() {
        guard welcomeScreenShownInVersion != Bundle.main.appVersionLong || Bundle.main.appVersionLong.contains("0.0.0-dev") else {
            return
        }
        log.notice("Showing welcome window")
        WelcomeWindowController().show()
        welcomeScreenShownInVersion = Bundle.main.appVersionLong
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !Self.isRunningInPreview else { return true }
        log.notice("applicationShouldHandleReopen (hasVisibleWindows: \(hasVisibleWindows))")
        if launch.started(for: .app) {
            // The launch never said what it was for, and now the app is
            // opened: this is its launch window.
            openLaunchWindow()
            showWelcomeWindowIfDue()
            NSApp.activate(ignoringOtherApps: true)
        } else if !hasVisibleWindows {
            archiveWindowManager?.openArchiveWindow()
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }
    
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // A Finder action under way has work still to come: what closed was
        // its progress window between two archives, or a panel it asked in.
        if ExtractionProgressCenter.shared.isRunningAction {
            return false
        }
        if quitOnLastWindowClosed {
            return true
        }
        // the progress window of a Finder action that had started the app
        return finderLaunchIsOver
    }

    /// Whether the app was started for a Finder action and has done it, with
    /// nothing left on screen. It quits then, and takes its Dock icon with it,
    /// whatever "Quit on last window closed" says: nobody opened this app.
    private var finderLaunchIsOver: Bool {
        let center = ExtractionProgressCenter.shared
        return launch.isOver(
            usedAsApp: archiveWindowManager?.hasOpenedWindow ?? false,
            actionUnderWay: center.isRunningAction,
            // a failed job is on screen in a moment: the progress window puts it up and keeps it
            somethingOnScreen: center.hasFailedJobs || NSApp.windows.contains { $0.isVisible || $0.isMiniaturized }
        )
    }

    /// Asked for in #119: don't let the app quit silently while an
    /// extraction is running. Nor while Finder's compress is, which has no
    /// window that would say so.
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
#if DEBUG
        // The extraction demo keeps a job "active" on purpose; don't let the
        // quit-guard alert block the relaunches that drive its screenshots.
        if ExtractionDemo.isRequested { return .terminateNow }
#endif
        guard let running = ExtractionProgressCenter.shared.runningKind else {
            return .terminateNow
        }

        // "extraction" / "compression": the lines an extraction always logged, as they were
        let what = running == .extraction ? "extraction" : "compression"
        log.notice("Quit requested while \(what) is running — asking user")
        let alert = NSAlert()
        alert.alertStyle = .warning
        switch running {
        case .extraction:
            alert.messageText = String(localized: .appExtractionInProgress)
            alert.informativeText = String(localized: .appQuitDuringExtractionWarning)
        case .compression:
            alert.messageText = String(localized: .appCompressionInProgress)
            alert.informativeText = String(localized: .appQuitDuringCompressionWarning)
        }
        alert.addButton(withTitle: String(localized: .commonCancel))
        alert.addButton(withTitle: String(localized: .appQuitAnyway))

        if alert.runModal() == .alertFirstButtonReturn {
            log.notice("Quit cancelled — \(what) continues")
            return .terminateCancel
        }
        log.notice("Quit forced during \(what)")
        // What is being compressed is stopped first, and the quit waits for it:
        // the writer then removes what it had written. Quit under it, and half
        // an archive stays behind under the name the whole one was to have.
        Task { @MainActor in
            await ExtractionProgressCenter.shared.cancelAll(.compression, waitingUpTo: .seconds(5))
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
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

    func showDropWindow() {
        dropWindowController?.show()
    }
}
