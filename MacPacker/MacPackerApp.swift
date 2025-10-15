//
//  MacPackerApp.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 01.08.23.
//

import FinderSync
import SwiftUI
#if !STORE
import Sparkle
#endif
import TailBeatKit

@main
struct MacPackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    
    #if !STORE
    private let updaterController: SPUStandardUpdaterController
    #endif
    
    let appState: AppState = AppState.shared
    
    init() {
        #if !STORE
        // If you want to start the updater manually, pass false to startingUpdater and call .startUpdater() later
        // This is where you can also pass an updater delegate if you need one
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        #endif
        
        Logger.start()
        
        // register all handlers
        ArchiveHandlerXad.register()
        ArchiveHandlerLz4.register()
        ArchiveHandlerZip.registerZip()
    }
    
    var body: some Scene {
        Settings {
            PreferencesView()
                .environmentObject(appDelegate)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button {
                    appDelegate.openAboutWindow()
                } label: {
                    Text("About \(Bundle.main.appName)", comment: "Link to the About page of the app. The order depends on the language. For example: English: About MacPacker, Japanese: MacPackerについて")
                }
            }
#if !STORE
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
#endif
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @AppStorage("welcomeScreenShownInVersion") private var welcomeScreenShownInVersion = "0.0"
    private var openWithUrls: [URL] = []
    private var archiveWindowManager: ArchiveWindowManager? = nil
    
    override init() {
        super.init()
        archiveWindowManager = ArchiveWindowManager(appDelegate: self)
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
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
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        TailBeat.start()
        
        Logger.log("finish launching")
        
        // make sure that at least one window will be shown
        // even if it is empyt
        archiveWindowManager?.openArchiveWindow()
        
        if let appVersion = Version(Bundle.main.appVersionLong),
           let welcomeVersion = Version(welcomeScreenShownInVersion) {
            if appVersion > welcomeVersion {
                Logger.debug("Higher app version detected, showing welcome screen")
                WelcomeWindowController.shared.show()
                welcomeScreenShownInVersion = Bundle.main.appVersionLong
            }
        }
        
        #if !DEBUG
        if FIFinderSyncController.isExtensionEnabled == false {
            FIFinderSyncController.showExtensionManagementInterface()
        }
        #endif
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        CacheCleaner.shared.clean()
    }
    
    func openAboutWindow() {
        
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
}
