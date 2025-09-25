//
//  PreferencesView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 02.12.23.
//

import Foundation
import SwiftUI

struct PreferencesView: View {
    var body: some View {
        VStack {
            TabView {
                GeneralSettingsView()
                    .tabItem {
                        Image(systemName: "gear")
                        Text("General", comment: "General settings")
                    }
                    .tag(0)
                
                AdvancedSettingsView()
                    .tabItem {
                        Image(systemName: "exclamationmark.octagon")
                        Text("Advanced", comment: "Advanced settings")
                    }
                    .tag(1)
                
                #if DEBUG
                DebugSettingsView()
                    .tabItem {
                        Image(systemName: "ant")
                        Text(verbatim: "Debug")
                    }
                #endif
            }
        }
        .frame(width: 640)
        .onAppear {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
