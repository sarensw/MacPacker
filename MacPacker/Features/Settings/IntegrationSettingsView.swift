//
//  IntegrationSettingsView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 09.01.26.
//

import FinderMenu
import FinderSync
import Foundation
import SwiftUI

struct IntegrationSettingsView: View {
    private let applicationSupportDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first

    @State var isFinderSyncEnabled: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                Text("File provider extension")
                    .frame(width: 160, alignment: .trailing)

                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        FIFinderSyncController.showExtensionManagementInterface()
                    } label: {
                        Text("Manage in System Settings")
                    }
                    .disabled(applicationSupportDirectory == nil)

                    HStack(spacing: 4) {
                        Circle()
                            .frame(width: 6, height: 6)
                            .foregroundStyle(isFinderSyncEnabled ? Color.green : Color.red)

                        Text(FIFinderSyncController.isExtensionEnabled ? "Enabled" : "Disabled")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button {
                            isFinderSyncEnabled = FIFinderSyncController.isExtensionEnabled
                            print(isFinderSyncEnabled)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                        .controlSize(.small)
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 240, alignment: .leading)
            }

            Divider()

            HStack(alignment: .top) {
                Text("Context menu:", comment: "Settings label above the list of entries the MacPacker Finder context menu offers")
                    .frame(width: 160, alignment: .trailing)

                VStack(alignment: .leading) {
                    ForEach(FinderMenuItem.allCases, id: \.self) { item in
                        FinderMenuItemToggle(item: item)
                    }
                }
                .padding(.leading, 8)
                .toggleStyle(.checkbox)
                .frame(width: 240, alignment: .leading)
            }

            HStack(alignment: .top) {
                Text("Nest in a submenu:", comment: "Setting that puts the MacPacker Finder entries into a MacPacker submenu instead of directly into the Finder context menu")
                    .frame(width: 160, alignment: .trailing)

                HStack {
                    FinderMenuCascadedToggle()
                }
                .padding(.leading, 8)
                .toggleStyle(.checkbox)
                .frame(width: 240, alignment: .leading)
            }
        }
        .padding()
        .onAppear {
            isFinderSyncEnabled = FIFinderSyncController.isExtensionEnabled
        }
    }
}

/// One checkbox per context menu entry, stored in the app group so the Finder
/// extension — a separate process — reads the same value.
private struct FinderMenuItemToggle: View {
    private let item: FinderMenuItem
    @AppStorage private var isOn: Bool

    init(item: FinderMenuItem) {
        self.item = item
        _isOn = AppStorage(
            wrappedValue: item.isEnabledByDefault,
            FinderMenuSettings.key(for: item),
            store: FinderMenuSettings.defaults
        )
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            label
        }
    }

    /// Mirrors the wording of the menu entry itself, with the parts that depend
    /// on the selection written as placeholders — the same way 7-Zip lists them.
    @ViewBuilder
    private var label: some View {
        switch item {
        case .open:
            Text("Open archive", comment: "Context menu entry in the settings list: opens the selection in an archive window")
        case .extractHere:
            Text("Extract Here", comment: "Context menu entry in the settings list: extracts next to the archive")
        case .extractToFolder:
            Text("Extract to folder", comment: "Context menu entry in the settings list: extracts into a new folder named after the archive")
        case .addToArchive:
            Text("Add to Archive…", comment: "Context menu entry in the settings list: opens a new-archive window for the selection")
        case .compressToZip:
            Text("Compress to zip", comment: "Context menu entry in the settings list: compresses the selection straight to a zip file")
        case .compressTo7z:
            Text("Compress to 7z", comment: "Context menu entry in the settings list: compresses the selection straight to a 7z file")
        case .extractToChosenFolder:
            Text("Extract to a chosen folder…", comment: "Context menu entry in the settings list: asks where to extract, then extracts there")
        case .compressToDatedZip:
            Text("Compress to zip with date and time", comment: "Context menu entry in the settings list: compresses the selection to a zip whose name carries the current date and time")
        case .compressEachSeparately:
            Text("Compress each item separately", comment: "Context menu entry in the settings list: compresses every selected item into its own zip")
        case .compressFolderContents:
            Text("Compress a folder’s contents", comment: "Context menu entry in the settings list: compresses what is inside a folder, without the folder itself")
        }
    }
}

private struct FinderMenuCascadedToggle: View {
    @AppStorage(FinderMenuSettings.cascadedKey, store: FinderMenuSettings.defaults)
    private var isCascaded: Bool = true

    var body: some View {
        Toggle(isOn: $isCascaded) {
            Text("Show in a MacPacker submenu", comment: "Setting that nests the Finder context menu entries under a MacPacker submenu instead of listing them directly")
        }
    }
}

#Preview {
    IntegrationSettingsView()
}
