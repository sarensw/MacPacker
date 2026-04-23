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
    @Environment(\.openSettings) private var openSettings
    
    init() {
        Logger.start()
    }
    
    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button {
                    appDelegate.appState.selectedSettingsTab = .about
                    openSettings()
                } label: {
                    Text("About \(Bundle.main.displayName)", comment: "Link to the About page of the app. The order depends on the language. For example: English: About MacPacker, Japanese: MacPackerについて")
                }
            }
#if !STORE
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: appDelegate.updaterController.updater)
            }
#endif
            
            CommandGroup(replacing: .newItem) {
                Button {
                    appDelegate.openNewArchiveWindow()
                } label: {
                    Label {
                        Text("New \(Bundle.main.displayName) Window")
                    } icon: {
                        Image(systemName: "plus.rectangle")
                    }
                }
                
                Button {
                    appDelegate.openArchiveUsingOpenPanel()
                } label: {
                    Label {
                        Text("Open…")
                    } icon: {
                        Image(systemName: "arrow.up.right.square")
                    }
                }
            }
        }
    }
}

