//
//  ArchiveView.swift
//  MacPacker
//
//  Created by Arenswald, Stephan (059) on 31.08.23.
//

import Foundation
import SwiftUI

class ArchiveContainer: ObservableObject {
    @Published var isReloadNeeded: Bool = false
}

struct ArchiveView: View {
    @Environment(\.openWindow) var openWindow
    @EnvironmentObject var state: ArchiveState
    @State private var isDraggingOver = false
    @State private var selection: IndexSet?
    
    func openPreviewer(for url: URL) {
        openWindow(id: "Previewer")
    }
    
    var body: some View {
        VStack {
            ArchiveTableViewRepresentable(
                selection: $selection,
                openWindow: openPreviewer,
                isReloadNeeded: $state.archiveContainer.isReloadNeeded,
                archive: $state.archive) {
                    if let archive = state.archive {
                        return archive.currentStackEntry
                    }
                    return nil
                }
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
            if let indexes = selection,
                let archive = state.archive {
                if let selectedIndex = indexes.first {
                    let archiveItem = archive.items[selectedIndex]
                    state.selectedItem = archiveItem
                } else if indexes.isEmpty {
                    state.selectedItem = nil
                }
            }
        }
        .onKeyPress(.space) {
            if let archive = state.archive,
               let selectedItem = state.selectedItem,
               let url = archive.extractFileToTemp(selectedItem) {
                openWindow(id: "Previewer", value: url)
            }
            return .handled
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
