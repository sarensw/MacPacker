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
                Text(.settingsCache)
                    .frame(width: 160, alignment: .trailing)
                
                VStack(alignment: .leading) {
                    Button {
                        if let url = applicationSupportDirectory {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                        }
                    } label: {
                        Text(.settingsOpenCacheDirectory)
                    }
                    .help(.settingsShowApplicationSupportFolder)
                    .disabled(applicationSupportDirectory == nil)
                    
                    Button {
                        CacheCleaner().clean()
                    } label: {
                        Text(.settingsClearCache)
                    }
                    .help(.settingsClearCacheHint)
                    .disabled(applicationSupportDirectory == nil)
                }
                .frame(width: 240, alignment: .leading)
            }
            
            HStack(alignment: .top) {
                Text(.settingsLogs)
                    .frame(width: 160, alignment: .trailing)

                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        exportLogs()
                    } label: {
                        Text(.settingsExportLogs)
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
            alert.messageText = String(localized: .errorExportFailed)
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}


