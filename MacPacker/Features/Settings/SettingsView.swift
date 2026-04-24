//
//  PreferencesView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 02.12.23.
//

import Foundation
import SwiftUI

enum SettingsViewTab: Int, CaseIterable, Identifiable {
    case general
    case formats
    case advanced
    case integration
    case about
    case debug
    
    var id: Int { self.rawValue }
}

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    
    var body: some View {
        VStack {
            TabView(selection: $state.selectedSettingsTab) {
                GeneralSettingsView()
                    .tabItem {
                        Image(systemName: "gear")
                        Text("General", comment: "General settings")
                    }
                    .tag(SettingsViewTab.general)
                
                FormatSettingsView()
                    .tabItem {
                        Image(systemName: "doc.badge.gearshape")
                        Text("Archive Formats")
                    }
                    .tag(SettingsViewTab.formats)
                
                AdvancedSettingsView()
                    .tabItem {
                        Image(systemName: "exclamationmark.octagon")
                        Text("Advanced", comment: "Advanced settings")
                    }
                    .tag(SettingsViewTab.advanced)
                
                IntegrationSettingsView()
                    .tabItem {
                        Image(systemName: "puzzlepiece.extension")
                        Text("Extensions")
                    }
                    .tag(SettingsViewTab.integration)
                
                AboutSettingsView()
                    .tabItem {
                        Image(systemName: "info.circle")
                        Text("About")
                    }
                    .tag(SettingsViewTab.about)
                
                #if DEBUG
                DebugSettingsView()
                    .tabItem {
                        Image(systemName: "ant")
                        Text(verbatim: "Debug")
                    }
                    .tag(SettingsViewTab.debug)
                #endif
            }
        }
        .frame(width: 640)
        .onAppear {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}

#Preview {
    SettingsView()
}
