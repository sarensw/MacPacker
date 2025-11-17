//
//  ContentView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 01.08.23.
//

import AppKit
import Core
import SwiftUI

struct PathControlView: NSViewRepresentable {
    var path: String?

    func makeNSView(context: Context) -> NSPathControl {
        let pathControl = NSPathControl()
        pathControl.url = path.flatMap { URL(fileURLWithPath: $0) }
        pathControl.isEditable = false
        pathControl.pathStyle = .standard
        return pathControl
    }

    func updateNSView(_ nsView: NSPathControl, context: Context) {
        nsView.url = path.flatMap { URL(fileURLWithPath: $0) }
    }
}


struct ContentView: View {
    // settings
    @AppStorage(Keys.settingBreadcrumbPosition) var breadcrumbPosition: BreadcrumbPosition = .bottom
    
    // environment
    @Environment(\.openWindow) var openWindow
    @EnvironmentObject var state: AppState
    @EnvironmentObject var archiveState: ArchiveState
    
    // state
    @State private var selectedFileItemID: Set<ArchiveItem.ID> = []
    
    var body: some View {
        VStack(spacing: 0) {
            if breadcrumbPosition == .top {
                if let selectedItem = archiveState.archive?.selectedItem {
                    BreadcrumbView(for: selectedItem)
                }
                
                Divider()
                    .frame(height: 1)
                    .background(.quinary)
            }
            
            ArchiveView()
            
            if breadcrumbPosition == .bottom {
                Divider()
                    .frame(height: 1)
                    .background(.quinary)
                
                if let selectedItem = archiveState.archive?.selectedItem {
                    BreadcrumbView(for: selectedItem)
                }
            }
        }
        .if(!.macOS13) { view in
            view.toolbar {
                ArchiveContentToolbarView(
                    archiveState: archiveState
                )
            }
        }
        .navigationTitle(archiveState.archive == nil ? Bundle.main.appName : archiveState.archive!.name)
        .environmentObject(archiveState)
    }
    
    private var selection: Binding<Set<ArchiveItem.ID>> {
        Binding(
            get: { selectedFileItemID },
            set: {
                selectedFileItemID = $0
                print("selection changed to \(String(describing: selectedFileItemID))")
            }
        )
    }
}
