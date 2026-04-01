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
            if let icon = archiveItem.icon {
                Image(nsImage: icon)
                    .resizable(resizingMode: .stretch)
                    .frame(
                        width: 14,
                        height: 14)
            }
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
    @EnvironmentObject private var archiveState: ArchiveState

    private let selectedItem: ArchiveItem

    init(for selectedItem: ArchiveItem) {
        self.selectedItem = selectedItem
    }

    private var items: [ArchiveItem] {
        var result: [ArchiveItem] = []
        var current: ArchiveItem? = selectedItem

        while let item = current {
            result.append(item)
            current = item.parent.flatMap { archiveState.entries[$0] }
        }

        return result.reversed()
    }

    var body: some View {
        HStack(alignment: .center) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    ForEach(items.indices, id: \.self) { index in
                        BreadcrumbItemView(
                            archiveItem: items[index],
                            onTap: {
                                archiveState.open(item: items[index])
                            }
                        )

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
