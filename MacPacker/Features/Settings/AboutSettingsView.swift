//
//  AboutSettingsView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 12.04.26.
//

import Pandalytics
import SwiftUI

struct AboutSettingsView: View {
    @AppStorage("checkForUpdates") var checkForUpdates: SettingUpdateCheck = .automatically
    @AppStorage("updateBetaChannelOn") var updateBetaChannelOn: Bool = false
    
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                if let nsImage = NSImage(named: "AppIcon") {
                    Image(nsImage: nsImage)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading) {
                        Text(Bundle.main.displayName)
                            .font(.largeTitle)
                            .fontWeight(.light)
                        Text(Bundle.main.appVersionLong)
                            .font(.title2)
                            .fontWeight(.light)
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
#if !STORE
                        if let updaterController = appState.updaterController {
                            CheckForUpdatesView(updater: updaterController.updater)
                        }
#endif
                        
                        Button {
                            openURL(Constants.changelogURL)
                        } label: {
                            Text("What's New")
                        }
                    }
                    
#if !STORE
                    VStack(alignment: .leading) {
                        Toggle("Automatically check for updates", isOn: Binding (
                            get: { checkForUpdates == .automatically },
                            set: { newValue in
                                if newValue == true {
                                    checkForUpdates = .automatically
                                } else {
                                    checkForUpdates = .manually
                                }
                            }
                        ))
                        .toggleStyle(.checkbox)
                        
                        Toggle("Include Beta updates", isOn: $updateBetaChannelOn)
                        .toggleStyle(.checkbox)
                        .padding(.leading, 20)
                        .disabled(checkForUpdates == .manually)
                    }
#endif
                    
                    Text(verbatim: "© 2023-2026 Stephan Arenswald")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(verbatim: "Licensed under the GNU General Public License v3.0 (GPL-3.0-or-later). This is free software: you can redistribute it and/or modify it under the terms of the GPL.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(verbatim: "No warranty. See LICENSE for details.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 24)
            }
            .padding(.leading, 32)
            
            Spacer()
            
            Divider()
                .padding(.vertical, 16)
            
            HStack {
                Button {
                    AckWindowController().show()
                } label: {
                    Text("Acknowledgements")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                
                Button {
                    openURL(Constants.privacyURL)
                } label: {
                    Text("Privacy Policy")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                
                Button {
                    openURL(Constants.termsURL)
                } label: {
                    Text("Terms of Service")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button {
                    openURL(Constants.homepageURL)
                } label: {
                    Text("Visit Website")
                }
                
                Button {
                    openURL(URL(string: "mailto:\(Constants.supportMail)")!)
                } label: {
                    Text("Contact Us")
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 24)
    }
}

#Preview {
    AboutSettingsView()
        .frame(width: 640, height: 480)
}
