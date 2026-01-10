//
//  IntegrationSettingsView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 09.01.26.
//

import FinderSync
import Foundation
import SwiftUI

struct IntegrationSettingsView: View {
    private let applicationSupportDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    
    @State var isFinderSyncEnabled: Bool = false
    
    var body: some View {
        VStack {
            HStack(alignment: .top) {
                Text("settings.extensions.findersync.label", comment: "Label for the MacPacker Finder extension settings access and status.")
                    .frame(width: 160, alignment: .trailing)
                
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        FIFinderSyncController.showExtensionManagementInterface()
                    } label: {
                        Text("settings.extensions.findersync.manage", comment: "Opens the File Provider system settings to enable or disable the MacPacker Finder extension. The name of this label should represent how 'File provider extesions' is spelled in the user's local language. To check the correct translation open System Settings > General > Login Items & Extensions > Extensions > By Category > 'File Providers' (or 'File Providers' in the user's local language > open that and the first sentence in the dialog will tell you what to use)")
                    }
                    .disabled(applicationSupportDirectory == nil)
                    
                    HStack(spacing: 4) {
                        Circle()
                            .frame(width: 6, height: 6)
                            .foregroundStyle(isFinderSyncEnabled ? Color.green : Color.red)
                        
                        Text(isFinderSyncEnabled ? "enabled" : "disabled")
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
        }
        .padding()
        .onAppear {
            isFinderSyncEnabled = FIFinderSyncController.isExtensionEnabled
        }
    }
}
