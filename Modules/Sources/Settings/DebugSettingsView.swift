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
        }
        .padding()
    }
}
