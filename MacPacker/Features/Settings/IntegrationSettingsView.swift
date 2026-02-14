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
        }
        .padding()
        .onAppear {
            isFinderSyncEnabled = FIFinderSyncController.isExtensionEnabled
        }
    }
}
