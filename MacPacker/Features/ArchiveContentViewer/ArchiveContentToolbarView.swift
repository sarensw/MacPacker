//
//  ArchiveContentToolbarView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 08.09.25.
//

import SwiftUI

extension NSImage {
    static func menuIcon(named name: String, pointSize: CGFloat = 16) -> NSImage {
        let src = NSImage(imageLiteralResourceName: name)
        src.size = NSSize(width: pointSize, height: pointSize)
        return src
    }
}

struct ArchiveContentToolbarView: ToolbarContent {
    @Environment(\.openWindow) var openWindow
    @Environment(\.openURL) var openURL
    @State private var isExportingItem: Bool = false
    @State private var isExportingAll: Bool = false
    
    let archiveState: ArchiveState
    let contentService: ArchiveContentService = ArchiveContentService()
    let service: ArchiveService = ArchiveService()
    
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu("More", systemImage: "ellipsis.circle") {
                if #available(macOS 14, *) {
                    SettingsLink() {
                        Label("Settings...", systemImage: "gear")
                            .labelStyle(.titleAndIcon)
                    }
                } else {
                    Button {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } label: {
                        Label("Settings", systemImage: "gear")
                            .labelStyle(.titleAndIcon)
                    }
                }
                
                Divider()
                
                Button {
                    if let url = archiveState.archive?.url {
                        contentService.openGetInfoWnd(for: [url])
                    }
                } label: {
                    Label("Archive info", systemImage: "info.circle")
                        .labelStyle(.titleAndIcon)
                }
                
                Divider()
                
                Menu("More Apps", systemImage: "plus.square.dashed") {
                    Button {
                        openURL(URL(string: "https://filefillet.com/?utm_source=macpacker&utm_content=moremenu&utm_medium=ui")!)
                    } label: {
                        Label {
                            Text("FileFillet")
                        } icon: {
                            Image(nsImage: .menuIcon(named: "FileFillet", pointSize: 16))
                        }
                        .labelStyle(.titleAndIcon)
                    }
                }
                .labelStyle(.titleAndIcon)
                
                Button {
                    openURL(URL(string: "https://macpacker.app/?utm_source=macpacker&utm_content=moremenu&utm_medium=ui")!)
                } label: {
                    Label("Website", systemImage: "link")
                        .labelStyle(.titleAndIcon)
                }
                
                Button {
                    openURL(URL(string: "https://github.com/sarensw/MacPacker/")!)
                } label: {
                    Label("GitHub", systemImage: "link")
                        .labelStyle(.titleAndIcon)
                }
                
                Button {
                    openWindow(id: "About")
                } label: {
                    Label("About MacPacker", systemImage: "info.square")
                        .labelStyle(.titleAndIcon)
                }
            }
            
            
        }
        ToolbarItemGroup(placement: .secondaryAction) {
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
