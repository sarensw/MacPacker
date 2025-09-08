//
//  ContentView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 01.08.23.
//

import SwiftUI
import AppKit

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
    @AppStorage("setting.breadcrumbPosition") var breadcrumbPosition: BreadcrumbPosition = .bottom
    
    // environment
    @Environment(\.openWindow) var openWindow
    @StateObject var archiveState: ArchiveState = ArchiveState()
    @EnvironmentObject var state: AppState
    
    // state
    @State private var selectedFileItemID: Set<ArchiveItem.ID> = []
    
    var body: some View {
        VStack(spacing: 0) {
            if breadcrumbPosition == .top {
                BreadcrumbView(archive: archiveState.archive ?? nil)
                
                Divider()
                    .frame(height: 1)
                    .background(.quinary)
            }
            
            ArchiveView()
            
            if breadcrumbPosition == .bottom {
                Divider()
                    .frame(height: 1)
                    .background(.quinary)
                
                BreadcrumbView(archive: archiveState.archive ?? nil)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    if let archive = archiveState.archive,
                       let selectedItem = archiveState.selectedItem,
                       let url = archive.extractFileToTemp(selectedItem) {
                        openWindow(id: "Previewer", value: url)
                    }
                } label: {
                    Image(systemName: "text.page.badge.magnifyingglass")
                }
                
                Button {
                    if let url = archiveState.archive?.url {
                        openGetInfoWnd(for: [url])
                    }
                } label: {
                    Image(systemName: "info.circle")
                }
                
                if #available(macOS 14, *) {
                    SettingsLink() {
                        Label("Settings", systemImage: "gear")
                    }
                } else {
                    Button {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
        }
        .onOpenURL { url in
            self.archiveState.loadUrl(url)
        }
        .navigationTitle(archiveState.archive == nil ? "MacPacker" : archiveState.archive!.name)
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
    
    func openGetInfoWnd(for urls: [URL]) {
        let pBoard = NSPasteboard(name: NSPasteboard.Name(rawValue: "pasteBoard_\(UUID().uuidString )") )
        
        pBoard.writeObjects(urls as [NSPasteboardWriting])
        
        NSPerformService("Finder/Show Info", pBoard)
    }
}

#Preview {
    ContentView(archiveState: ArchiveState(completePath: "/MacPackerTests/TestArchives/archiveNested1.zip"))
        .environmentObject(AppState.shared)
        .frame(width: 480, height: 352)
}
