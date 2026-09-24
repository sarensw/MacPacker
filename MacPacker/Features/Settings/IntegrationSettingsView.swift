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
                Text(.settingsFileProviderExtension)
                    .frame(width: 160, alignment: .trailing)

                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        FIFinderSyncController.showExtensionManagementInterface()
                    } label: {
                        Text(.settingsManageInSystemSettings)
                    }
                    .disabled(applicationSupportDirectory == nil)

                    HStack(spacing: 4) {
                        Circle()
                            .frame(width: 6, height: 6)
                            .foregroundStyle(isFinderSyncEnabled ? Color.green : Color.red)

                        Text(isFinderSyncEnabled ? .commonEnabled : .commonDisabled)
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
                Text(.settingsContextMenu)
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
                Text(.settingsNestInSubmenu)
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
            Text(.commonOpenArchive)
        case .extractHere:
            Text(.commonExtractHere)
        case .extractToFolder:
            Text(.settingsExtractToFolder)
        case .addToArchive:
            Text(.commonAddToArchive)
        case .compressToZip:
            Text(.settingsCompressToZip)
        case .compressTo7z:
            Text(.settingsCompressTo7Z)
        case .extractToChosenFolder:
            Text(.settingsExtractToChosenFolder)
        case .compressToDatedZip:
            Text(.settingsCompressToZipDateTime)
        case .compressEachSeparately:
            Text(.settingsCompressEachItemSeparately)
        case .compressFolderContents:
            Text(.settingsCompressFolderContents)
        }
    }
}

private struct FinderMenuCascadedToggle: View {
    @AppStorage(FinderMenuSettings.cascadedKey, store: FinderMenuSettings.defaults)
    private var isCascaded: Bool = true

    var body: some View {
        Toggle(isOn: $isCascaded) {
        }
    }
}

#Preview {
    IntegrationSettingsView()
}
