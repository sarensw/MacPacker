//
//  MacPackerApp.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 01.08.23.
//

import FinderSync
import Core
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
    
    init() {
        #if !STORE
        // If you want to start the updater manually, pass false to startingUpdater and call .startUpdater() later
        // This is where you can also pass an updater delegate if you need one
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        #endif
        
        Logger.start()
    }
    
    var body: some Scene {
        Settings {
            SettingsView()
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
            
            CommandGroup(replacing: .newItem) {
                Button {
                    appDelegate.openNewArchiveWindow()
                } label: {
                    Label {
                        Text(.newWindow(Bundle.main.appName))
                    } icon: {
                        Image(systemName: "plus.rectangle")
                    }
                }
                
                Button {
                    appDelegate.openArchiveUsingOpenPanel()
                } label: {
                    Label {
                        Text(.`open`)
                    } icon: {
                        Image(systemName: "arrow.up.right.square")
                    }
                }
            }
        }
    }
}

