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
    
    @State private var showPasswordSheet: Bool = false
    @State private var passwordContinuation: CheckedContinuation<String?, Never>?
    
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
        .toolbar {
            ArchiveContentToolbarView(
                archiveState: archiveState
            )
        }
        .onAppear {
            if self.archiveState.passwordProvider == nil {
                let passwordProvider: ArchivePasswordUserProvider = { request in
                    
                    await withCheckedContinuation { continuation in
                        Task { @MainActor in
                            self.passwordContinuation = continuation
                            self.showPasswordSheet = true
                        }
                    }
                }
                
                self.archiveState.passwordProvider = passwordProvider
            }
        }
        .sheet(isPresented: $showPasswordSheet) {
            PasswordView(
                onSubmit: { password in
                    passwordContinuation?.resume(returning: password)
                    passwordContinuation = nil
                    showPasswordSheet = false
                },
                onCancel: {
                    passwordContinuation?.resume(returning: nil)
                    passwordContinuation = nil
                    showPasswordSheet = false
                }
            )
            .frame(width: 366)
        }
        .navigationTitle(archiveState.hasArchive == false ? Bundle.main.displayName : archiveState.name!)
        .navigationSubtitle("\(archiveState.diff.count > 0 ? "Edited • " : "")\(archiveState.url == nil ? "" : archiveState.url!.path)")
        .environmentObject(archiveState)
    }
}
