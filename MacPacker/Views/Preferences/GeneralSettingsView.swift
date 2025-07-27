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
    @AppStorage("setting.breadcrumbPosition") var breadcrumbPosition: BreadcrumbPosition = .bottom
    
    var body: some View {
        VStack {
            VStack {
                VStack {
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
            }
            .padding()
        }
    }
}

#Preview {
    GeneralSettingsView()
}
