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
                    Text(.commonAbout(Bundle.main.displayName))
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
                        Text(.commonNewArchive)
                    } icon: {
                        Image(systemName: "doc.badge.plus")
                    }
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button {
                    appDelegate.openNewArchiveWindow()
                } label: {
                    Label {
                        Text(.commonNewWindow(Bundle.main.displayName))
                    } icon: {
                        Image(systemName: "plus.rectangle")
                    }
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button {
                    appDelegate.showDropWindow()
                } label: {
                    Label {
                        Text(.commonQuickCompressWindow)
                    } icon: {
                        Image(systemName: "shippingbox")
                    }
                }
                .keyboardShortcut("d", modifiers: [.command, .option])
            }

            ArchiveCommands()

            CommandGroup(after: .newItem) {

                Button {
                    appDelegate.openArchiveUsingOpenPanel()
                } label: {
                    Label {
                        Text(.commonOpen)
                    } icon: {
                        Image(systemName: "arrow.up.right.square")
                    }
                }
            }
        }
    }
}

