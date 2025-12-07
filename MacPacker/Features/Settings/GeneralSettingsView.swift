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
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                Text("Columns:", comment: "Let's the user choose to show or hide columns in the archive window")
                    .frame(width: 160, alignment: .trailing)
                
                VStack(alignment: .leading) {
                    Toggle(isOn: $showCompressedSize) {
                        Text("Packed Size", comment: "Column that shows the packed size of the archive files")
                    }
                    Toggle(isOn: $showUncompressedSize) {
                        Text("Size", comment: "Column that shows the unpacked size of the archive files")
                    }
                    Toggle(isOn: $showModificationDate) {
                        Text("Date Modified", comment: "Column that shows the date the file was modified")
                    }
                    Toggle(isOn: $showPermissions) {
                        Text("Permissions", comment: "Column that shows the file permissions")
                    }
                }
                .padding(.leading, 8)
                .toggleStyle(.checkbox)
                .frame(width: 240, alignment: .leading)
            }
            
            Divider()
            
            HStack(alignment: .top) {
                Text("Breadcrumb position:", comment: "Allows the user to change the breadcrumb position to either top or bottom of the archive window")
                    .frame(width: 160, alignment: .trailing)
                
                HStack {
                    Picker(String(""), selection: $breadcrumbPosition) {
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
