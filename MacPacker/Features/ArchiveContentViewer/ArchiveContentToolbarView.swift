//
//  ArchiveContentToolbarView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 08.09.25.
//

import SwiftUI

struct ArchiveContentToolbarView: ToolbarContent {
    @Environment(\.openWindow) var openWindow
    @State private var isExportingItem: Bool = false
    @State private var isExportingAll: Bool = false
    
    let archiveState: ArchiveState
    let contentService: ArchiveContentService = ArchiveContentService()
    let service: ArchiveService = ArchiveService()
    
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                if let archive = archiveState.archive,
                   let selectedItem = archiveState.selectedItems.first,
                   let url = archive.extractFileToTemp(selectedItem) {
                    openWindow(id: "Previewer", value: url)
                }
            } label: {
                Label("Preview", systemImage: "text.page.badge.magnifyingglass")
            }
            
            Button {
                if let url = archiveState.archive?.url {
                    contentService.openGetInfoWnd(for: [url])
                }
            } label: {
                Label("Archive info", systemImage: "info.circle")
            }
            
            if #available(macOS 14, *) {
                SettingsLink() {
                    Label("Settings", systemImage: "gear")
                }
            } else {
                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        ToolbarItemGroup(placement: .secondaryAction) {
            Button {
                if archiveState.archive != nil {
                    isExportingItem.toggle()
                }
            } label: {
                Label("Extract selected", image: "custom.document.badge.arrow.down")
            }
            .fileImporter(
                isPresented: $isExportingItem,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result,
                   let folderURL = urls.first {
                    if let archive = archiveState.archive {
                        service.extract(
                            archive: archive,
                            items: archiveState.selectedItems,
                            to: folderURL)
                    }
                }
            }
            
            Button {
                if archiveState.archive != nil {
                    isExportingAll.toggle()
                }
            } label: {
                Label("Extract archive", image: "custom.shippingbox.badge.arrow.down")
            }
            .fileImporter(
                isPresented: $isExportingAll,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result,
                   let folderURL = urls.first {
                    if let archive = archiveState.archive {
                        service.extract(
                            archive: archive,
                            to: folderURL)
                    }
                }
            }
        }
    }
}
