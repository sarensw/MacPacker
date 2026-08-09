//
//  DebugSettings.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 25.09.25.
//

import AppKit
import SwiftUI
import tb

struct DebugSettingsView: View {
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                Text("Windows:", comment: "Debug settings section for opening windows")
                    .frame(width: 160, alignment: .trailing)
                
                VStack(alignment: .leading) {
                    Button {
                        WelcomeWindowController().show()
                    } label: {
                        Text("Show Welcome window", comment: "Debug action that opens the welcome window")
                    }
                    Button {
                        appState.selectedSettingsTab = .about
                        openSettings()
                    } label: {
                        Text("Show About window", comment: "Debug action that opens the About settings window")
                    }
                    Button {
                        QuickLookHarnessWindowController().show()
                    } label: {
                        Text("Open Quick Look Harness…", comment: "Debug action that opens the Quick Look test window")
                    }
                }
                .padding(.leading, 8)
                .toggleStyle(.checkbox)
                .frame(width: 240, alignment: .leading)
            }
            
            HStack(alignment: .top) {
                Text("Meta:", comment: "Debug settings section for application metadata")
                    .frame(width: 160, alignment: .trailing)
                
                VStack(alignment: .leading) {
                    HStack {
                        Text(verbatim: Bundle.main.bundlePath)
                            .help(Bundle.main.bundlePath)
                        
                        Button {
                            NSWorkspace.shared.open(Bundle.main.bundleURL.deletingLastPathComponent())
                        } label: {
                            Image(systemName: "arrow.up.right.square")
                        }
                    }
                }
                .frame(width: 240, alignment: .leading)
            }

            HStack(alignment: .top) {
                Text("Logs:", comment: "Debug settings section for logs")
                    .frame(width: 160, alignment: .trailing)

                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        exportLogs()
                    } label: {
                        Text("Export Logs…", comment: "Debug action that exports the current session logs")
                    }
                    Text("Saves this session's logs (notice level and above) as NDJSON you can send for diagnosis.", comment: "Explanation of the debug log export action")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 240, alignment: .leading)
            }
        }
        .padding()
    }

    private func exportLogs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MacPacker-logs.ndjson"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try tb.exportRecentLogs(since: Date(timeIntervalSinceNow: -24 * 60 * 60), to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            let alert = NSAlert()
            alert.messageText = String(localized: "Could not export logs", comment: "Title of the alert shown when debug log export fails")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
