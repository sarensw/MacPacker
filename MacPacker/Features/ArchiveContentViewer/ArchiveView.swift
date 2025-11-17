//
//  ArchiveView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 31.08.23.
//

import Foundation
import QuickLook
import Core
import SwiftUI

struct ArchiveView: View {
    @Environment(\.openWindow) var openWindow
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
                isReloadNeeded: $state.isReloadNeeded,
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
        .onChange(of: selection) { _ in
            if let indexes = selection,
               let archive = state.archive,
               let selectedItem = archive.selectedItem,
               let children = selectedItem.children {
                
                state.selectedItems.removeAll()
                for index in indexes {
                    let archiveItem = children[index]
                    state.selectedItems.append(archiveItem)
                }
                
                // in case quick look is open right now, then change the
                // previewed item
                if self.state.previewItemUrl != nil {
                    state.updateSelectedItemForQuickLook()
                }
            }
        }
        .quickLookPreview($state.previewItemUrl)
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
        
        state.load(from: url)
    }
}
