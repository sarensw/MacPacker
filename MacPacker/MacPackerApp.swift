//
//  MacPackerApp.swift
//  MacPacker
//
//  Created by Arenswald, Stephan (059) on 01.08.23.
//

import SwiftUI
#if !STORE
import Sparkle
#endif

@main
struct MacPackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate
    #if !STORE
    private let updaterController: SPUStandardUpdaterController
    #endif
    @Environment(\.openWindow) var openWindow
    let appState: AppState = AppState.shared
    
    init() {
        #if !STORE
        // If you want to start the updater manually, pass false to startingUpdater and call .startUpdater() later
        // This is where you can also pass an updater delegate if you need one
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        #endif
    }
    
    var body: some Scene {
        WindowGroup(id: "MainWindow") {
            ContentView()
                .environmentObject(appState)
        }
        .restorationBehavior(.disabled)
        
        Window("", id: "About") {
            AboutView()
                .frame(width: 460, height: 420)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commandsRemoved()
        .defaultPosition(.center)
        
        Settings {
            PreferencesView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About MacPacker") {
                    openWindow(id: "About")
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    @AppStorage("welcomeScreenShownInVersion") private var welcomeScreenShownInVersion = "0.0"
    private var openWithUrls: [URL] = []
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if Bundle.main.appVersionLong > welcomeScreenShownInVersion {
            WelcomeWindowController.shared.show()
            welcomeScreenShownInVersion = Bundle.main.appVersionLong
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        CacheCleaner.shared.clean()
    }
}
