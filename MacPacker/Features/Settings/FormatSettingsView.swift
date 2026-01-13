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
    @EnvironmentObject private var appDelegate: AppDelegate

    @State private var rows: [ArchiveFormatSettings] = []
    @State private var selection: ArchiveFormatSettings.ID?
    
    @State private var showEngineInfo: Bool = false

    fileprivate func refreshFormatConfig() {
        var result: [ArchiveFormatSettings] = []

        // Take all known formats from the catalog
        for type in appDelegate.catalog.getAllTypes() {
            let formatId = type.id

            // Ask the store (via catalog) which engines exist for this format
            let engineOptions = appDelegate.archiveEngineConfigStore.engineOptions(for: formatId)
            guard !engineOptions.isEmpty else {
                // No engines configured for this format – skip it
                continue
            }

            // Current engine = user override or catalog default
            guard let selectedEngine =
                    appDelegate.archiveEngineConfigStore.selectedEngine(for: formatId) else { continue }

            let engines = engineOptions.compactMap { ArchiveEngineType(configId: $0.id) }
            let extString = type.extensions.joined(separator: ", ")

            // Default app detection: keep false for now (toggle is disabled anyway)
            let isDefaultApp = false

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
        alert.messageText = "Set MacPacker as the default app"
        alert.informativeText = "To make MacPacker the default for a file type: Right-click a file → 'Get Info' → choose MacPacker under 'Open with:' → click 'Change All…' to apply it to all similar archives."
        alert.alertStyle = .informational
        alert.runModal()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                        Text("How to set \(Bundle.main.appName) as default?")
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
                    // "MacPacker includes several archive engines. The default is recommended; alternative engines can help with format-specific problems. Keep in mind that engine support varies by format."
                    Text("Info on Engines")
                        .frame(width: 160)
                        .padding()
                }
            }
        }
        .padding()
        .frame(minHeight: 400)
        .onAppear {
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
                    appDelegate.archiveEngineConfigStore.setSelectedEngine(newValue, for: identifier)
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
    }
}

