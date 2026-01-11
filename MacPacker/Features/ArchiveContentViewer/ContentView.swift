//
//  ContentView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 01.08.23.
//

import AppKit
import Core
import SwiftUI

struct CancelEngineActionButton: View {
    @State var hovered: Bool = false
    
    let pressed: () -> Void
    
    var body: some View {
        Button {
            pressed()
        } label: {
            Image(systemName: "x.circle.fill")
                .foregroundStyle(hovered ? .primary : .secondary)
                .onHover { hovered in
                    self.hovered = hovered
                }
        }
        .buttonStyle(.plain)
        .padding(.leading, 8)
        .padding(.trailing, 4)
    }
}

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
            
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if archiveState.isBusy {
                    CancelEngineActionButton() {
                        archiveState.cancelCurrentOperation()
                    }
                    
                    ProgressView()
                        .scaleEffect(0.4)
                        .frame(height: 14)
                        .progressViewStyle(.circular)
                    
                    Text(verbatim: "\(archiveState.statusText ?? "")")
                        .fontWeight(.light)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    
                    if let progress = archiveState.progress {
                        Text(verbatim: "\(progress)%")
                            .fontWeight(.light)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .padding(.leading, 4)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 4)
            .frame(height: 24)
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
