//
//  SettingsGeneralView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 02.12.23.
//

import Core
import Foundation
import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(Keys.settingBreadcrumbPosition) var breadcrumbPosition: BreadcrumbPosition = .bottom
    @AppStorage(Keys.showColumnCompressedSize) var showCompressedSize: Bool = true
    @AppStorage(Keys.showColumnUncompressedSize) var showUncompressedSize: Bool = true
    @AppStorage(Keys.showColumnModificationDate) var showModificationDate: Bool = true
    @AppStorage(Keys.showColumnPosixPermissions) var showPermissions: Bool = false
    @AppStorage(Keys.showParentRow) var showParentRow: Bool = false
    @AppStorage(Keys.quitOnLastWindowClosed) var quitOnLastWindowClosed: Bool = false
    @AppStorage(Keys.showMenuBarItem) var showMenuBarItem: Bool = false
    @AppStorage(Keys.rememberRecentArchives) var rememberRecentArchives: Bool = true
    @AppStorage(Keys.smartExtraction, store: .macPackerShared) var smartExtraction: Bool = true

    @AppStorage(Keys.excludeMacMetadata) var excludeMacMetadata = false
    @AppStorage(Keys.requireWindowsCompatibleNames) var requireWindowsCompatibleNames = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                Text(.settingsColumns)
                    .frame(width: 200, alignment: .trailing)
                
                VStack(alignment: .leading) {
                    Toggle(isOn: $showCompressedSize) {
                        Text(.columnPackedSize)
                    }
                    Toggle(isOn: $showUncompressedSize) {
                        Text(.columnSize)
                    }
                    Toggle(isOn: $showModificationDate) {
                        Text(.columnDateModified)
                    }
                    Toggle(isOn: $showPermissions) {
                        Text(.columnPermissions)
                    }
                }
                .padding(.leading, 8)
                .toggleStyle(.checkbox)
                .frame(width: 240, alignment: .leading)
            }

            HStack(alignment: .top) {
                Text(.settingsShowParentFolderEntry)
                    .frame(width: 200, alignment: .trailing)

                HStack {
                    Toggle(isOn: $showParentRow) {}
                }
                .padding(.leading, 8)
                .frame(width: 240, alignment: .leading)
            }

            Divider()
            
            HStack(alignment: .top) {
                Text(.settingsBreadcrumbPosition)
                    .frame(width: 200, alignment: .trailing)
                
                HStack {
                    Picker(String(""), selection: $breadcrumbPosition) {
                        ForEach(BreadcrumbPosition.allCases, id: \.self) { position in
                            breadcrumbPositionLabel(position)
                                .tag(position)
                        }
                    }
                }
                .frame(width: 240, alignment: .leading)
            }
            
            HStack(alignment: .top) {
                Text(.settingsQuitOnLastWindowClosed)
                    .frame(width: 200, alignment: .trailing)
                
                HStack {
                    Toggle(isOn: $quitOnLastWindowClosed) {}
                }
                .padding(.leading, 8)
                .frame(width: 240, alignment: .leading)
            }

            HStack(alignment: .top) {
                Text(.settingsShowInMenuBar)
                    .frame(width: 200, alignment: .trailing)

                HStack {
                    Toggle(isOn: $showMenuBarItem) {}
                }
                .padding(.leading, 8)
                .frame(width: 240, alignment: .leading)
            }

            HStack(alignment: .top) {
                Text(.settingsRememberRecentArchives)
                    .frame(width: 200, alignment: .trailing)

                HStack {
                    Toggle(isOn: $rememberRecentArchives) {}
                }
                .padding(.leading, 8)
                .frame(width: 240, alignment: .leading)
            }

            Divider()

            HStack(alignment: .top) {
                Text(.settingsSmartExtraction)
                    .frame(width: 200, alignment: .trailing)

                HStack {
                    Toggle(isOn: $smartExtraction) {}
                }
                .padding(.leading, 8)
                .frame(width: 240, alignment: .leading)
            }
            HStack(alignment: .top) {
                Text("Exclude Mac-specific metadata", comment: "Global compression setting label")
                    .frame(width: 200, alignment: .trailing)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $excludeMacMetadata) { EmptyView() }
                        .labelsHidden()
                        .accessibilityIdentifier("settings.excludeMacMetadata")
                    Toggle("Windows-compatible filenames", isOn: $requireWindowsCompatibleNames)
                        .accessibilityIdentifier("settings.windowsCompatibleNames")
                        .help("Stops before saving and lists incompatible or conflicting filenames. Files are never renamed.")
                        .disabled(!excludeMacMetadata)
                    Text("Leaves out .DS_Store, resource forks and Finder metadata when compressing or saving. Hidden flags and custom folder icons are not preserved.", comment: "Consequences of excluding Mac metadata from archives")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 8)
                .frame(width: 240, alignment: .leading)
            }
        }
        .padding()
        // Turning it off is a privacy switch, so what was collected goes with it —
        // the start page's "Clear" is out of reach once the section is hidden.
        .onChange(of: rememberRecentArchives) { _, isOn in
            if !isOn { RecentArchives.clear() }
        }
    }
    
    /// Returns the localized label for a breadcrumb position in the settings picker.
    @ViewBuilder
    private func breadcrumbPositionLabel(_ position: BreadcrumbPosition) -> some View {
        switch position {
        case .top:
            Text(.commonTop)
        case .bottom:
            Text(.commonBottom)
        case .none:
            Text(.commonNone)
        }
    }
}

#Preview {
    GeneralSettingsView()
}
