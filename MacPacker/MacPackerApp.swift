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
import tb
#if DEBUG
import SandboxPilotKit
#endif

private let log = tb.Logger(subsystem: "app.MacPacker", category: "lifecycle")

@main
struct MacPackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openSettings) private var openSettings
    
    init() {
        tb.start()
        Keys.registerDefaults()
        log.notice("MacPackerApp.init — app process starting")
        
        #if DEBUG
        SandboxPilot.start()
        #endif
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
                    appDelegate.openCreateArchiveWindow()
                } label: {
                    Label {
                        Text("New Archive", comment: "File menu entry that opens a window with a new, empty archive ready to be filled and saved")
                    } icon: {
                        Image(systemName: "doc.badge.plus")
                    }
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button {
                    appDelegate.openNewArchiveWindow()
                } label: {
                    Label {
                        Text("New \(Bundle.main.displayName) Window")
                    } icon: {
                        Image(systemName: "plus.rectangle")
                    }
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            ArchiveCommands()

            CommandGroup(after: .newItem) {
                
                Button {
                    appDelegate.openArchiveUsingOpenPanel()
                } label: {
                    Label {
                        Text("Open…", comment: "A label for a button that allows the user to open an archive from disk.")
                    } icon: {
                        Image(systemName: "arrow.up.right.square")
                    }
                }
            }
        }
    }
}

