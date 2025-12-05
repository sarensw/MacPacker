//
//  DebugSettings.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 25.09.25.
//

import App
import SwiftUI

struct DebugSettingsView: View {
    @EnvironmentObject var appDelegate: AppDelegate
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                Text(verbatim: "Windows:")
                    .frame(width: 160, alignment: .trailing)
                
                VStack(alignment: .leading) {
                    Button {
                        WelcomeWindowController().show()
                    } label: {
                        Text(verbatim: "Show Welcome window")
                    }
                    Button {
                        appDelegate.openAboutWindow()
                    } label: {
                        Text(verbatim: "Show About window")
                    }
                }
                .padding(.leading, 8)
                .toggleStyle(.checkbox)
                .frame(width: 240, alignment: .leading)
            }
            
            HStack(alignment: .top) {
                Text(verbatim: "Meta:")
                    .frame(width: 160, alignment: .trailing)
                
                VStack(alignment: .leading) {
                    HStack {
                        Text(verbatim: Bundle.main.bundlePath)
                            .help(Bundle.main.bundlePath)
                        
                        Button {
                            NSWorkspace.shared.open(Bundle.main.bundleURL.deletingLastPathComponent())
                        } label: {
                            Image(systemName: "arrow.up.right.square")
                        }
                    }
                }
                .frame(width: 240, alignment: .leading)
            }
        }
        .padding()
    }
}
