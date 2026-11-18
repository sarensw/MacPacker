//
//  AdvancedSettingsView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 17.06.25.
//

import Core
import Foundation
import SwiftUI
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "cache")

struct AdvancedSettingsView: View {
    @EnvironmentObject private var appState: AppState
    private let applicationSupportDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    /// The archive the analysis sheet is showing, if it is up.
    @State private var analyzedArchive: URL?

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
                        Task { await openQuickLookCache() }
                    } label: {
                        Text(.settingsOpenQuickLookCache)
                    }

                    Button {
                        Task { await clearCache() }
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

                    Button {
                        analyzedArchive = chooseArchiveToAnalyze()
                    } label: {
                        Text(.settingsAnalyzeArchive)
                    }
                }
                .frame(width: 240, alignment: .leading)
            }
        }
        .padding()
        .sheet(isPresented: Binding(
            get: { analyzedArchive != nil },
            set: { if !$0 { analyzedArchive = nil } }
        )) {
            if let analyzedArchive {
                ArchiveAnalysisView(
                    url: analyzedArchive,
                    analyzer: ArchiveAnalyzer(catalog: appState.catalog, engineSelector: appState.engineSelector))
            }
        }
    }

    /// The archive to analyze. Any file can be picked: one MacPacker does not
    /// take for an archive is what a report is most needed for.
    private func chooseArchiveToAnalyze() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// The app's cache, then Quick Look's.
    private func clearCache() async {
        await CacheCleaner().removeAll()
        guard let caches = await quickLookCaches() else { return }
        await Sandbox.access(url: caches) {
            await CacheCleaner().removeAll(in: caches.appending(component: "ta", directoryHint: .isDirectory))
        }
    }

    private func openQuickLookCache() async {
        guard let caches = await quickLookCaches() else { return }
        // Finder is shown only what the app may read itself.
        let shown = Sandbox.accessSync(url: caches) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: caches.path)
        }
        log.info("Quick Look cache opened", context: ["shown": "\(shown)"])
    }

    /// Quick Look's `Caches`. It is in the extension's own container, which the
    /// sandbox opens to the app only once the user grants it: the first time, a
    /// panel asks; later, the stored grant is used. Nil when Quick Look never
    /// ran or the user said no.
    private func quickLookCaches() async -> URL? {
        guard let home = FolderAccessStore.homeFolder, let app = Bundle.main.bundleIdentifier else { return nil }
        let caches = home.appending(
            path: "Library/Containers/\(app).QuickLookExtension/Data/Library/Caches", directoryHint: .isDirectory)
        // Quick Look never ran: no panel for a folder that is not there.
        guard FileManager.default.fileExists(atPath: caches.path) else {
            log.info("No Quick Look cache")
            return nil
        }
        return await FolderAccessStore.shared.ensureAccess(forFolder: caches) ? caches : nil
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


