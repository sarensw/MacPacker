//
//  FormatSettingsView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 02.12.25.
//

import Core
import SwiftUI

struct ArchiveFormatSettings: Identifiable {
    let id: ArchiveTypeId
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
        let catalog = ArchiveTypeCatalog.shared
        
        var result: [ArchiveFormatSettings] = []
        
        let configs = appDelegate.archiveEngineConfigStore.configs
        for archiveTypeId in configs.keys {
            if let config = configs[archiveTypeId],
               let type = catalog.getType(for: config.formatId) {
                let defaultApp = NSWorkspace.shared.urlForApplication(toOpen: type.uti)
                let containsAppName = defaultApp?.path.contains(Bundle.main.appName) ?? false
                let isDefaultApp = defaultApp?.path == Bundle.main.bundleURL.path || containsAppName
                
                let afs = ArchiveFormatSettings(
                    id: config.formatId,
                    name: config.formatId.rawValue,
                    extensions: type.extensions.joined(separator: ", "),
                    engines: config.options.map(\.engineId),
                    selectedEngine: config.selectedEngineId,
                    defaultOpen: isDefaultApp
                )
                result.append(afs)
            }
        }
        
        result.sort(by: { $0.name < $1.name })
        
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
                TableColumn("") {
                    defaultToggle(identifier: $0.id, default: $0.defaultOpen)
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
                    Label("Refresh", systemImage: "arrow.counterclockwise")
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
                    Text("settings_engines_info", comment: "Info text about archive engines in MacPacker")
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
    func defaultToggle(identifier: ArchiveTypeId, default: Bool) -> some View {
        let binding = Binding<Bool>(
            get: { `default` },
            set: {
                if let id = rows.firstIndex(where: { $0.id == identifier }) {
                    self.rows[id].defaultOpen = $0
                    
                    let setToDefault = $0
                    if setToDefault {
                        // TODO: Enable this when we are able to set default app
//                        showInfoToSetAsDefault()
                    } else {
                        // TODO: Enable this when we are able to set default app
                    }
                }
            }
        )
        Toggle(isOn: binding, label: { Text(verbatim: "") })
            .frame(alignment: .center)
        // TODO: Remove this when we are able to set default app
            .disabled(true)
    }
    
    @ViewBuilder
    func supportedPicker(identifier: ArchiveTypeId, selectedEngine: ArchiveEngineType, supportedEngines: [ArchiveEngineType]) -> some View {
        let binding = Binding<ArchiveEngineType>(
            get: { selectedEngine },
            set: {
                if let id = rows.firstIndex(where: { $0.id == identifier }) {
                    self.rows[id].selectedEngine = $0
                    self.appDelegate.archiveEngineConfigStore.setSelectedEngine($0, for: identifier)
                }
            }
        )
        Picker("", selection: binding) {
            ForEach(supportedEngines) { supportedEngine in
                Text(supportedEngine.rawValue).tag(supportedEngine)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
    }
}

