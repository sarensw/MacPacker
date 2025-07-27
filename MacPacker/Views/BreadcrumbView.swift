//
//  BreadcrumbView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 05.05.25.
//

import SwiftUI

struct BreadcrumbItem {
    var symbol: String = "document"
    var icon: NSImage?
    var name: String
}

struct BreadcrumbItemView: View {
    var breadcrumbItem: BreadcrumbItem
    var showName: Bool = true
    var onTap: (() -> Void)?
    
    @State private var isPressed = false
    
    var body: some View {
        HStack(spacing: 2) {
            if let icon = breadcrumbItem.icon {
                Image(nsImage: icon)
                    .resizable(resizingMode: .stretch)
                    .frame(
                        width: 14,
                        height: 14)
            } else {
                Image(systemName: breadcrumbItem.symbol)
                    .frame(width: 14, height: 14)
            }
            if showName {
                Text(breadcrumbItem.name)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .font(.subheadline)
        .fontWeight(.light)
        .foregroundColor(.primary)
        .opacity(isPressed ? 0.6 : 1.0)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    isPressed = true
                }
                .onEnded { _ in
                    isPressed = false
                    onTap?()
                }
        )
    }
}

struct BreadcrumbView: View {
    // environment
    @EnvironmentObject var archiveState: ArchiveState
    
    // state
    
    // variables
    private var url: URL?
    private var items: [BreadcrumbItem] = []
    private var archive: Archive2?
    
    init(archive: Archive2?) {
        self.archive = archive
        
        if let archive {
            for stackItem in archive.stack {
                var icon: NSImage?
                if stackItem.type == .Directory || stackItem.type == .ArchiveDirectory {
                    icon = NSWorkspace.shared.icon(for: .folder)
                } else {
                    icon = getNSImageByExtension(fileName: stackItem.name)
                }
                items.append(BreadcrumbItem(
                    icon: icon,
                    name: stackItem.name
                ))
            }
        }
    }
    
    func getNSImageByExtension(fileName: String) -> NSImage? {
        let fileExtension = (fileName as NSString).pathExtension
        let icon = NSWorkspace.shared.icon(forFileType: fileExtension)
        return icon
    }
    
    func getNSImage(url: URL) -> NSImage? {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        print("Loading image for: \(url.path)")
        return icon
    }
    
    var body: some View {
        HStack(alignment: .center) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .firstTextBaseline,spacing: 4) {
                    ForEach(items.indices, id: \.self) { index in
                        BreadcrumbItemView(breadcrumbItem: items[index], onTap: {
                            if items.count > 1 {
                                do {
                                    for _ in 0..<self.items.count-index-1 {
                                        try _ = self.archive?.open(.parent)
                                    }
                                    self.archiveState.archiveContainer.isReloadNeeded = true
                                    self.archiveState.selectedItem = nil
                                } catch {
                                    print(error)
                                }
                            }
                        })
                        
                        if index != items.indices.last {
                            Image(systemName: "chevron.right")
                                .resizable()
                                .frame(width: 3, height: 6)
                                .fontWeight(.black)
                                .foregroundColor(.primary.opacity(0.6))
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 4)
                .frame(height: 24)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
