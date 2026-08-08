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
    /// The request the sheet is currently answering, so it can name the archive
    /// and say that the previous attempt was rejected.
    @State private var passwordRequest: ArchivePasswordRequest?

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
        .searchable(text: Binding(
            get: { archiveState.searchText },
            set: { archiveState.search($0) }
        ))
        .modifier(FocusSearchWhenLaunchedIntoOne())
        .onAppear {
            if self.archiveState.passwordProvider == nil {
                let passwordProvider: ArchivePasswordUserProvider = { request in

                    await withCheckedContinuation { continuation in
                        Task { @MainActor in
                            self.passwordContinuation = continuation
                            self.passwordRequest = request
                            self.showPasswordSheet = true
                        }
                    }
                }
                
                self.archiveState.passwordProvider = passwordProvider
            }
        }
        // A failed open ends in reset(), so the window falls back to its empty
        // state: without this the user's drag or double-click just appears to do
        // nothing. Extraction failures are deliberately not shown here — the
        // progress window already reports those.
        .alert(
            "Could not open archive",
            isPresented: Binding(
                get: { archiveState.openError != nil },
                set: { presented in
                    if !presented { archiveState.clearOpenError() }
                }
            ),
            presenting: archiveState.openError
        ) { _ in
            Button("OK", role: .cancel) { }
        } message: { reason in
            Text(verbatim: reason)
        }
        .sheet(isPresented: $showPasswordSheet) {
            PasswordView(
                request: passwordRequest,
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
        .navigationSubtitle(Text(verbatim: "\(archiveState.diff.count > 0 ? String(localized: "Edited • ", comment: "Window subtitle marker shown when the archive has unsaved changes") : "")\(archiveState.url == nil ? "" : archiveState.url!.deletingLastPathComponent().path + "/")"))
        .environmentObject(archiveState)
    }
}

/// Puts the cursor in the search field when the window was launched straight
/// into a search (`-SearchQuery`). An unfocused search field draws its text in
/// the placeholder's grey, which is all but unreadable in the light appearance —
/// and a window that opens showing filtered results should have the field live
/// anyway. `searchFocused` is macOS 15+; below that the field simply stays as it
/// is.
private struct FocusSearchWhenLaunchedIntoOne: ViewModifier {
    @FocusState private var focused: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content
                .searchFocused($focused)
                .task {
                    if LaunchParameters.value(LaunchParameters.searchQueryKey) != nil {
                        focused = true
                    }
                }
        } else {
            content
        }
    }
}
