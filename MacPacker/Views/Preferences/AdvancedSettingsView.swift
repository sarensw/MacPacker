//
//  AdvancedSettingsView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 17.06.25.
//

import Foundation
import SwiftUI

struct AdvancedSettingsView: View {
    private let applicationSupportDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    
    var body: some View {
        VStack {
            HStack(alignment: .top) {
                Text("Cache:")
                    .frame(width: 160, alignment: .trailing)
                
                VStack(alignment: .leading) {
                    Button {
                        if let url = applicationSupportDirectory {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                        }
                    } label: {
                        Text("Open cache directory")
                    }
                    .help("Show application support folder")
                    .disabled(applicationSupportDirectory == nil)
                    
                    Button {
                        CacheCleaner.shared.clean()
                    } label: {
                        Text("Clear cache")
                    }
                    .help("Clears all content from the cache")
                    .disabled(applicationSupportDirectory == nil)
                }
                .frame(width: 240, alignment: .leading)
            }
        }
        .padding()
    }
}


