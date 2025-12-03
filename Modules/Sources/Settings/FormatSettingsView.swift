//
//  FormatSettingsView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 02.12.25.
//

import App
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set \(Bundle.main.appName) as default app for:")
            
            Table(rows, selection: $selection) {
                TableColumn("") {
                    supportedToggle(identifier: $0.id, supported: $0.defaultOpen)
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
                    
                } label: {
                    Text("Select All")
                }
                
                Button {
                    
                } label: {
                    Text("Deselect All")
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
                    VStack {
                        Text("Info...")
                    }
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
            
            let catalog = ArchiveTypeCatalog.shared
            
            let configs = appDelegate.archiveEngineConfigStore.configs
            for archiveTypeId in configs.keys {
                if let config = configs[archiveTypeId] {
                    let afs = ArchiveFormatSettings(
                        id: config.formatId,
                        name: config.formatId.rawValue,
                        extensions: catalog.getType(for: config.formatId)!.extensions.joined(separator: ", "),
                        engines: config.options.map(\.engineId),
                        selectedEngine: config.selectedEngineId
                    )
                    rows.append(afs)
                }
            }
            
            rows.sort(by: { $0.name < $1.name })
        }
    }
    
    @ViewBuilder
    func supportedToggle(identifier: ArchiveTypeId, supported: Bool) -> some View {
        let binding = Binding<Bool>(
            get: { supported },
            set: {
                if let id = rows.firstIndex(where: { $0.id == identifier }) {
                    self.rows[id].defaultOpen = $0
                }
            }
        )
        Toggle(isOn: binding, label: { Text("") })
            .frame(alignment: .center)
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

