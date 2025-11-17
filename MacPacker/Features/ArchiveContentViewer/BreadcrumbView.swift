//
//  BreadcrumbView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 05.05.25.
//

import Core
import SwiftUI

struct BreadcrumbItemView: View {
    var archiveItem: ArchiveItem
    var showName: Bool = true
    var onTap: (() -> Void)?
    
    @State private var isPressed = false
    
    var body: some View {
        HStack(spacing: 2) {
            Image(nsImage: archiveItem.icon)
                .resizable(resizingMode: .stretch)
                .frame(
                    width: 14,
                    height: 14)
            if showName {
                Text(archiveItem.name)
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
    
    // variables
    private var items: [ArchiveItem] = []
    
    init(for selectedItem: ArchiveItem) {
        var parent: ArchiveItem? = selectedItem
        while parent != nil && parent!.type != .root {
            guard let p = parent else { break }
            items.insert(p, at: 0)
            parent = parent?.parent
        }
    }
    
    var body: some View {
        HStack(alignment: .center) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .firstTextBaseline,spacing: 4) {
                    ForEach(items.indices, id: \.self) { index in
                        BreadcrumbItemView(archiveItem: items[index], onTap: {
                            self.archiveState.archive?.selectedItem = items[index]
                            self.archiveState.isReloadNeeded = true
                            self.archiveState.selectedItems = []
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
