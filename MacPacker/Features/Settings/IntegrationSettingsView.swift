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
    @State private var areServicesOn = true

    var body: some View {
        VStack(spacing: 8) {
            // The Finder extension: the MacPacker menu and toolbar button,
            // which Finder leaves out in File Provider folders (#305).
            HStack(alignment: .top) {
                Text(.settingsFinderExtension)
                    .frame(width: 160, alignment: .trailing)

                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        FIFinderSyncController.showExtensionManagementInterface()
                    } label: {
                        Text(.settingsManageInSystemSettings)
                    }
                    .disabled(applicationSupportDirectory == nil)

                    StatusLine(isOn: isFinderSyncEnabled, refresh: refresh)

                    Text(.settingsFinderExtensionHint)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 240, alignment: .leading)
            }

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

            HStack(alignment: .top) {
                Text(.settingsFinderToolbarIcon)
                    .frame(width: 160, alignment: .trailing)

                // Finder takes the toolbar image only when it starts the
                // extension, and neither the app nor the extension can make
                // it start a new one.
                VStack(alignment: .leading, spacing: 4) {
                    ToolbarIconPicker()

                    Text(.settingsToolbarIconHint)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                }
                .frame(width: 240, alignment: .leading)
            }

            Divider()

            // The Services: Extract, Compress and Create archive in Finder's
            // context menu, File Provider folders included (#342). macOS keeps
            // whether they show, per user, where the sandbox can read but not
            // write: the app shows it and leads to the switches (#412).
            HStack(alignment: .top) {
                Text(.settingsServicesMenu)
                    .frame(width: 160, alignment: .trailing)

                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        FinderServices.openSettings()
                    } label: {
                        Text(.settingsManageInSystemSettings)
                    }

                    StatusLine(isOn: areServicesOn, refresh: refresh)

                    Text(.settingsServicesMenuHint)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 240, alignment: .leading)
            }
        }
        .padding()
        .onAppear(perform: refresh)
        // Back from System Settings: show what was switched there.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        isFinderSyncEnabled = FIFinderSyncController.isExtensionEnabled
        areServicesOn = FinderServices.isOn
    }
}

/// A green or red dot with Enabled or Disabled, and a button to look again.
private struct StatusLine: View {
    let isOn: Bool
    let refresh: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .frame(width: 6, height: 6)
                .foregroundStyle(isOn ? Color.green : Color.red)

            Text(isOn ? .commonEnabled : .commonDisabled)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .foregroundStyle(.secondary)
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
        case .testArchive:
            Text(.commonTestArchive)
        case .compressToDatedZip:
            Text(.settingsCompressToZipDateTime)
        case .compressForWindows:
            Text(.settingsCompressToZipForWindows)
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

/// The icon of the MacPacker button in Finder's toolbar.
private struct ToolbarIconPicker: View {
    @AppStorage(FinderMenuSettings.toolbarIconKey, store: FinderMenuSettings.defaults)
    private var icon: ToolbarIcon = .colored

    var body: some View {
        Picker(String(""), selection: $icon) {
            Text(.settingsToolbarIconColored).tag(ToolbarIcon.colored)
            Text(.settingsToolbarIconSubtle).tag(ToolbarIcon.subtle)
        }
    }
}

#Preview {
    IntegrationSettingsView()
}
