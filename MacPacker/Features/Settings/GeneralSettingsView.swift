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
    @AppStorage(Keys.oneClickExtraction) var oneClickExtraction: Bool = false
    @AppStorage(Keys.oneClickExtractionDestination) var oneClickDestination: OneClickExtractionDestination = .archiveFolder

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
                Text("One-click extraction", comment: "General settings label for automatically extracting archives opened from Finder.")
                    .frame(width: 200, alignment: .trailing)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $oneClickExtraction) {
                        Text("Extract archives when opened", comment: "General settings toggle. Opening a recognized archive from Finder extracts it instead of showing the archive browser.")
                    }
                    Picker(selection: $oneClickDestination) {
                        Text("Same folder as the archive", comment: "One-click extraction destination: put the contents directly beside the archive.")
                            .tag(OneClickExtractionDestination.sameFolder)
                        Text("Folder named after the archive", comment: "One-click extraction destination: create a folder beside the archive using the archive's name.")
                            .tag(OneClickExtractionDestination.archiveFolder)
                        Text("Ask for a location", comment: "One-click extraction destination: show a folder picker each time archives are opened.")
                            .tag(OneClickExtractionDestination.chooseFolder)
                    } label: {
                        Text("Extract to", comment: "Label for the one-click extraction destination picker in General settings.")
                    }
                    .labelsHidden()
                    .disabled(!oneClickExtraction)
                }
                .padding(.leading, 8)
                .frame(width: 240, alignment: .leading)
            }

            HStack(alignment: .top) {
                Text(.settingsSmartExtraction)
                    .frame(width: 200, alignment: .trailing)

                HStack {
                    Toggle(isOn: $smartExtraction) {}
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
