//
//  PreferencesView.swift
//  MacPacker
//
//  Created by Arenswald, Stephan (059) on 02.12.23.
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
                        Text("General")
                    }
                    .tag(0)
                
                AdvancedSettingsView()
                    .tabItem {
                        Image(systemName: "exclamationmark.octagon")
                        Text("Advanced")
                    }
                    .tag(1)
            }
        }
        .frame(width: 640)
        .onAppear {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
