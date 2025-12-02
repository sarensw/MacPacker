//
//  FormatSettingsView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 02.12.25.
//

import App
import Core
import SwiftUI

struct FormatSettingsView: View {
    @EnvironmentObject private var appDelegate: AppDelegate
    
    @State private var bindings: [HandlerBinding] = []
    @State private var ids: [ArchiveTypeId] = []
    
    var body: some View {
        Table(ids) {
            TableColumn("File Format", value: \.rawValue)
            TableColumn("Extensions", value: \.rawValue)
            TableColumn("Engine", value: \.rawValue)
        }
        .onAppear {
            for binding in appDelegate.handlerRegistry.bindings {
                bindings.append(contentsOf: binding.value)
                ids.append(binding.key)
            }
            
            ids.sort { $0.rawValue < $1.rawValue }
        }
    }
}
