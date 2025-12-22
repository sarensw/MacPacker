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
    @State private var loading: Bool = false
    
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
                        Task {
                            await self.drop(fileURL)
                        }
                    }
                }
            }
            return true
        }
        .onAppear {
            if state.openWithUrls.count > 0 {
                Task {
                    await self.drop(state.openWithUrls[0])
                }
            }
        }
        .quickLookPreview($state.previewItemUrl)
    }
    
    //
    // functions
    //
    
//    @MainActor
    func drop(_ url: URL) async {
        state.clean()
        state.open(url: url)
    }
}
