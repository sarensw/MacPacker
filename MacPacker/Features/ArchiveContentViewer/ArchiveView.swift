//
//  ArchiveView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 31.08.23.
//

import Foundation
import SwiftUI

class ArchiveContainer: ObservableObject {
    @Published var isReloadNeeded: Bool = false
}

struct ArchiveView: View {
    @Environment(\.openWindow) var openWindow
    @EnvironmentObject private var appDelegate: AppDelegate
    @EnvironmentObject private var state: ArchiveState
    
    @AppStorage(Keys.showColumnCompressedSize) var showCompressedSize: Bool = true
    @AppStorage(Keys.showColumnUncompressedSize) var showUncompressedSize: Bool = true
    @AppStorage(Keys.showColumnModificationDate) var showModificationDate: Bool = true
    @AppStorage(Keys.showColumnPosixPermissions) var showPermissions: Bool = false
    
    @State private var isDraggingOver = false
    @State private var selection: IndexSet?
    
    var body: some View {
        VStack {
            ArchiveTableViewRepresentable(
                selection: $selection,
                isReloadNeeded: $state.archiveContainer.isReloadNeeded,
                showCompressedSizeColumn: $showCompressedSize,
                showUncompressedSizeColumn: $showUncompressedSize,
                showModificationDateColumn: $showModificationDate,
                showPosixPermissionsColumn: $showPermissions
            )
        }
        .border(isDraggingOver ? Color.blue : Color.clear, width: 2)
        .onDrop(of: ["public.file-url"], isTargeted: $isDraggingOver) { providers -> Bool in
            for provider in providers {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (data, error) in
                    if let data = data as? Data,
                        let fileURL = URL(dataRepresentation: data, relativeTo: nil) {
                        // Update the state variable with the accepted file URL
                        DispatchQueue.main.async {
                            self.drop(fileURL)
                        }
                    }
                }
            }
            return true
        }
        .onAppear {
            if state.openWithUrls.count > 0 {
                self.drop(state.openWithUrls[0])
            }
        }
        .onChange(of: selection) {
            print("selection changed: \(String(describing: selection))")
            if let indexes = selection,
                let archive = state.archive {
                
                state.selectedItems.removeAll()
                for index in indexes {
                    let archiveItem = archive.items[index]
                    state.selectedItems.append(archiveItem)
                }
            }
        }
        .onKeyPress(.space) {
            if let archive = state.archive,
                let selectedItem = state.selectedItems.first {

                // Only preview files, not directories
                if selectedItem.type == .file,
                   let url = archive.extractFileToTemp(selectedItem) {
                    appDelegate.openPreviewerWindow(for: url)
                    return .handled
                }
            }
            return .ignored
        }
        .onKeyPress(.return) {
            // Enter: Open selected item (enter directory or preview file)
            if let archive = state.archive,
                let selectedItem = state.selectedItems.first {
                // Only enter if it's a directory
                if selectedItem.type == .directory {
                    DispatchQueue.main.async {
                        do {
                            _ = try archive.open(selectedItem)
                            state.archiveContainer.isReloadNeeded = true
                            state.selectedItems = []
                            selection = nil
                        } catch {
                            print("Error opening directory: \(error)")
                        }
                    }
                    return .handled
                }
            }
            return .ignored
        }
        .onKeyPress("o") {
            // Cmd+O: Open the selected item (same as double-click)
            // Check for command modifier using NSEvent
            guard NSEvent.modifierFlags.contains(.command) else {
                return .ignored
            }

            if let archive = state.archive,
               let selectedItem = state.selectedItems.first {
                DispatchQueue.main.async {
                    do {
                        _ = try archive.open(selectedItem)
                        state.archiveContainer.isReloadNeeded = true
                        state.selectedItems = []
                        selection = nil
                    } catch {
                        print("Error opening item: \(error)")
                    }
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.downArrow) {
            // Cmd+Down: Enter the selected directory
            // Check for command modifier using NSEvent
            guard NSEvent.modifierFlags.contains(.command) else {
                return .ignored
            }

            if let archive = state.archive,
                let selectedItem = state.selectedItems.first,
                selectedItem.type == .directory {
                DispatchQueue.main.async {
                    do {
                        _ = try archive.open(selectedItem)
                        state.archiveContainer.isReloadNeeded = true
                        state.selectedItems = []
                        selection = nil
                    } catch {
                        print("Error opening directory: \(error)")
                    }
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.upArrow) {
            // Cmd+Up: Go up one level
            // Check for command modifier using NSEvent
            guard NSEvent.modifierFlags.contains(.command) else {
                return .ignored
            }

            if let archive = state.archive {
                // Check if we can go up (stack has more than one item)
                if archive.stack.count > 1 {
                    DispatchQueue.main.async {
                        do {
                            _ = try archive.open(ArchiveItem.parent)
                            state.archiveContainer.isReloadNeeded = true
                            state.selectedItems = []
                            selection = nil
                        } catch {
                            print("Error going up: \(error)")
                        }
                    }
                    return .handled
                }
            }
            return .ignored
        }
    }
    
    //
    // functions
    //
    
    func drop(_ url: URL) {
        // we're loading a new archive here, so clean up the current stack first
        if let arc = state.archive {
            do {
                try arc.clean()
            } catch {
                print("clean during drop failed")
                print(error)
            }
        }

        state.createArchive(url: url)
    }
}
