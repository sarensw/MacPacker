//
//  ContentView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 01.08.23.
//

import AppKit
import Core
import SwiftUI

struct ContentView: View {
    // settings
    @AppStorage(Keys.settingBreadcrumbPosition) var breadcrumbPosition: BreadcrumbPosition = .bottom
    
    // environment
    @Environment(\.openWindow) var openWindow
    @EnvironmentObject var archiveState: ArchiveState
    
    var body: some View {
        VStack(spacing: 0) {
            if breadcrumbPosition == .top {
                if let selectedItem = archiveState.selectedItem {
                    BreadcrumbView(for: selectedItem)
                }
                
                Divider()
                    .frame(height: 1)
                    .background(.quinary)
            }
            
            ArchiveView()
            
            if breadcrumbPosition == .bottom {
                if let selectedItem = archiveState.selectedItem {
                    Divider()
                        .frame(height: 1)
                        .background(.quinary)
                    
                    BreadcrumbView(for: selectedItem)
                }
            }
            
            Divider()
                .frame(height: 1)
                .background(.quinary)
            
            StatusBarView()
        }
        .if(!.macOS13) { view in
            view.toolbar {
                ArchiveContentToolbarView(
                    archiveState: archiveState
                )
            }
        }
        .navigationTitle(archiveState.url == nil ? Bundle.main.appName : archiveState.name!)
        .environmentObject(archiveState)
    }
}
