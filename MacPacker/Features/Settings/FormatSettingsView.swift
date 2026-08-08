//
//  FormatSettingsView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 02.12.25.
//

import Core
import SwiftUI

struct ArchiveFormatSettings: Identifiable {
    let id: String
    let name: String
    let extensions: String
    let engines: [ArchiveEngineType]
    var selectedEngine: ArchiveEngineType
    var defaultOpen: Bool = false
}

struct FormatSettingsView: View {
    @EnvironmentObject private var appState: AppState
    
    @State private var rows: [ArchiveFormatSettings] = []
    @State private var selection: ArchiveFormatSettings.ID?
    
    @State private var showEngineInfo: Bool = false
    /// Mirrors the store so the toggle and the picker enablement update together.
    @State private var isAutomatic: Bool = true
    
    private func isDefaultHandler(forUTI uti: String, bundleID: String) -> Bool {
        guard let handler = LSCopyDefaultRoleHandlerForContentType(
            uti as CFString,
            .all
        )?.takeRetainedValue() as String? else {
            return false
        }
        return handler == bundleID
    }

    fileprivate func refreshFormatConfig() {
        var result: [ArchiveFormatSettings] = []

        // Take all known formats from the catalog
        for type in appState.catalog.getAllTypes() {
            let formatId = type.id

            // Ask the store (via catalog) which engines exist for this format
            let engineOptions = appState.archiveEngineConfigStore.engineOptions(for: formatId)
            guard !engineOptions.isEmpty else {
                // No engines configured for this format – skip it
                continue
            }

            // Current engine = user override or catalog default
            guard let selectedEngine =
                    appState.archiveEngineConfigStore.selectedEngine(for: formatId) else { continue }

            let engines = engineOptions.compactMap { ArchiveEngineType(configId: $0.id) }
            let extString = type.extensions.joined(separator: ", ")

            // Default app detection: keep false for now (toggle is disabled anyway)
            var isDefaultApp = false
            if let uti = type.uti.first, isDefaultHandler(forUTI: uti, bundleID: Bundle.main.bundleIdentifier ?? "") {
                isDefaultApp = true
            }
            
            let afs = ArchiveFormatSettings(
                id: formatId,
                name: type.name,
                extensions: extString,
                engines: engines,
                selectedEngine: selectedEngine,
                defaultOpen: isDefaultApp
            )
            result.append(afs)
        }

        result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        rows = result
    }


    
    func showInfoToSetAsDefault() {
        let alert = NSAlert()
        alert.icon = NSImage(named: "AppIcon")
        alert.messageText = String(localized: "Set MacPacker as the default app", comment: "Title of the alert that explains how to set MacPacker as the default app for archive files.")
        alert.informativeText = String(localized: "To make MacPacker the default for a file type: Right-click a file → 'Get Info' → choose MacPacker under 'Open with:' → click 'Change All…' to apply it to all similar archives.", comment: "Instructions in the alert explaining how to set MacPacker as the default app for archive files in Finder.")
        alert.alertStyle = .informational
        alert.runModal()
    }
    
    /// Automatic engine selection. Most people neither know nor care which
    /// engine opens their archive, so MacPacker picks — and can switch to
    /// another engine when the preferred one can't read a particular file.
    /// Turning this off hands the choice back and makes it binding.
    private var automaticBinding: Binding<Bool> {
        Binding<Bool>(
            get: { isAutomatic },
            set: { newValue in
                isAutomatic = newValue
                appState.archiveEngineConfigStore.isAutomatic = newValue
                // The Engine column shows the catalog defaults again in
                // automatic mode, so the table has to be re-read.
                refreshFormatConfig()
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: automaticBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automatic engine selection")
                    Text("MacPacker chooses the engine for each archive, and tries another one if the first can't read it. Turn this off to choose engines yourself.", comment: "Explains the automatic engine selection toggle in the archive format settings")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(.bottom, 4)

            Divider()

            Text("Default status & engine settings:")

            Table(rows, selection: $selection) {
                TableColumn(String("")) {
                    defaultToggle(identifier: $0.id, defaultOpen: $0.defaultOpen)
                }
                .width(20)
                TableColumn("File Format", value: \.name)
                TableColumn("Extensions", value: \.extensions)
                TableColumn("Engine") {
                    supportedPicker(identifier: $0.id, selectedEngine: $0.selectedEngine, supportedEngines: $0.engines)
                }
            }
            .tableStyle(.bordered)
            
            HStack {
                Button {
                    refreshFormatConfig()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                
                Button {
                    showInfoToSetAsDefault()
                } label: {
                    Label {
                        Text("How to set \(Bundle.main.displayName) as default?")
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                }
                
                Spacer()
                
                Button {
                    showEngineInfo.toggle()
                } label: {
                    Label {
                        Text("Info on Engines")
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.orange)
                    }

                }
                .buttonStyle(.borderless)
                .popover(isPresented: $showEngineInfo) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MacPacker includes several archive engines. The default is recommended; alternative engines can help with format-specific problems. Keep in mind that engine support varies by format.", comment: "Help text to let users understand what the engine selection for each archive format is about")

                        Divider()

                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                            ForEach(ArchiveEngineType.allCases) { engine in
                                GridRow {
                                    Text(engine.rawValue)
                                    Text(engine.libraryVersion)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .font(.footnote)
                    }
                    .frame(width: 260)
                    .padding()
                }
            }
        }
        .padding()
        .frame(minHeight: 400)
        .onAppear {
            isAutomatic = appState.archiveEngineConfigStore.isAutomatic

            if !rows.isEmpty {
                return
            }

            refreshFormatConfig()
        }
    }
    
    @ViewBuilder
    func defaultToggle(identifier: String, defaultOpen: Bool) -> some View {
        let binding = Binding<Bool>(
            get: { defaultOpen },
            set: { newValue in
                if let index = rows.firstIndex(where: { $0.id == identifier }) {
                    rows[index].defaultOpen = newValue

                    let setToDefault = newValue
                    if setToDefault {
                        // TODO: Enable this when we are able to set default app
                        // showInfoToSetAsDefault()
                    } else {
                        // TODO: Handle "not default" case if needed
                    }
                }
            }
        )

        Toggle(isOn: binding, label: { Text(verbatim: "") })
            .frame(alignment: .center)
            // Currently just informational until default-app setting is implemented
            .disabled(true)
    }
    
    @ViewBuilder
    func supportedPicker(
        identifier: String,
        selectedEngine: ArchiveEngineType,
        supportedEngines: [ArchiveEngineType]
    ) -> some View {
        let binding = Binding<ArchiveEngineType>(
            get: { selectedEngine },
            set: { newValue in
                if let index = rows.firstIndex(where: { $0.id == identifier }) {
                    rows[index].selectedEngine = newValue
                    appState.archiveEngineConfigStore.setSelectedEngine(newValue, for: identifier)
                }
            }
        )

        Picker(String(""), selection: binding) {
            ForEach(supportedEngines, id: \.self) { engine in
                Text(engine.rawValue).tag(engine)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        // In automatic mode the column shows what MacPacker picked; editing it
        // would imply a choice that is not being honoured.
        .disabled(isAutomatic)
    }
}

