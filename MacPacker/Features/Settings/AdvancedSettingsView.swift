//
//  AdvancedSettingsView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 17.06.25.
//

import Foundation
import SwiftUI
import tb

struct AdvancedSettingsView: View {
    private let applicationSupportDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    
    var body: some View {
        VStack {
            HStack(alignment: .top) {
                Text("Cache:", comment: "Cache related settings")
                    .frame(width: 160, alignment: .trailing)
                
                VStack(alignment: .leading) {
                    Button {
                        if let url = applicationSupportDirectory {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                        }
                    } label: {
                        Text("Open cache directory", comment: "Allows the user to open the application support folder that holds the cache for temporarly extracted archive files")
                    }
                    .help("Show application support folder")
                    .disabled(applicationSupportDirectory == nil)
                    
                    Button {
                        CacheCleaner().clean()
                    } label: {
                        Text("Clear cache", comment: "Allows the user to clear the cache")
                    }
                    .help("Clears all content from the cache")
                    .disabled(applicationSupportDirectory == nil)
                }
                .frame(width: 240, alignment: .leading)
            }
            
            HStack(alignment: .top) {
                Text("Logs:", comment: "A label for the log related section in the advanced settings")
                    .frame(width: 160, alignment: .trailing)

                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        exportLogs()
                    } label: {
                        Text("Export Logs", comment: "A button that allows the user to export the app's recent logs")
                    }
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
            try tb.exportRecentLogs(since: Date(timeIntervalSinceNow: -60 * 60), to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            let alert = NSAlert()
            alert.messageText = "Export failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}


