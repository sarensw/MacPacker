//
//  SettingsGeneralView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 02.12.23.
//

import Foundation
import SwiftUI

enum BreadcrumbPosition: String, CaseIterable {
    case top
    case bottom
    case none
}

struct GeneralSettingsView: View {
    private let applicationSupportDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    @AppStorage(Keys.settingBreadcrumbPosition) var breadcrumbPosition: BreadcrumbPosition = .bottom
    @AppStorage(Keys.showColumnCompressedSize) var showCompressedSize: Bool = true
    @AppStorage(Keys.showColumnUncompressedSize) var showUncompressedSize: Bool = true
    @AppStorage(Keys.showColumnModificationDate) var showModificationDate: Bool = true
    @AppStorage(Keys.showColumnPosixPermissions) var showPermissions: Bool = false
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                Text("Columns:")
                    .frame(width: 160, alignment: .trailing)
                
                VStack(alignment: .leading) {
                    Toggle("Packed Size", isOn: $showCompressedSize)
                    Toggle("Size", isOn: $showUncompressedSize)
                    Toggle("Modified", isOn: $showModificationDate)
                    Toggle("Permissions", isOn: $showPermissions)
                }
                .padding(.leading, 8)
                .toggleStyle(.checkbox)
                .frame(width: 240, alignment: .leading)
            }
            
            Divider()
            
            HStack(alignment: .top) {
                Text("Breadcrumb position:")
                    .frame(width: 160, alignment: .trailing)
                
                HStack {
                    Picker("", selection: $breadcrumbPosition) {
                        ForEach(BreadcrumbPosition.allCases, id: \.self) { position in
                            Text(position.rawValue)
                                .tag(position)
                        }
                    }
                }
                .frame(width: 240, alignment: .leading)
            }
        }
        .padding()
    }
}

#Preview {
    GeneralSettingsView()
}
