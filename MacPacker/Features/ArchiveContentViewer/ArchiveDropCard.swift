//
//  ArchiveDropCard.swift
//  MacPacker
//
//  The card over the toolbar that opens a file dragged over an archive
//  window, while the list adds it (#251 G2).
//

import AppKit
import ArchivePreviewUI
import SwiftUI

/// A borderless child window over the toolbar and the tab bar: neither takes
/// a dropped file, so the card has to be a window of its own that does.
@MainActor
final class ArchiveDropCard: NSWindow {
    /// Opens what was dropped on the card.
    var open: (([URL]) -> Void)?
    /// The drag left the card, or ended over it.
    var onLeave: ((ArchiveFileDrag) -> Void)?

    fileprivate let model = Model()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        let dropView = DropView()
        dropView.card = self
        let host = NSHostingView(rootView: CardView(model: model))
        host.autoresizingMask = [.width, .height]
        dropView.addSubview(host)
        contentView = dropView
    }

    /// Shows the card over the toolbar of `window`: "Open", or "Create a new
    /// archive" for a file that is no archive.
    func show(over window: NSWindow, createsArchive: Bool) {
        let content = window.contentLayoutRect
        let frame = window.frame
        let zone = NSRect(x: frame.minX, y: frame.minY + content.maxY, width: frame.width, height: frame.height - content.maxY)
        guard zone.height > 0 else { return }
        model.createsArchive = createsArchive
        setFrame(zone, display: true)
        contentView?.subviews.first?.frame = contentView?.bounds ?? .zero
        if parent == nil { window.addChildWindow(self, ordered: .above) }
    }

    func hide() {
        model.isActive = false
        parent?.removeChildWindow(self)
        orderOut(nil)
    }

    fileprivate final class Model: ObservableObject {
        @Published var isActive = false
        @Published var createsArchive = false
    }
}

private final class DropView: NSView {
    weak var card: ArchiveDropCard?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        card?.model.isActive = true
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        card?.model.isActive = false
        card?.onLeave?(.exited)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        card?.onLeave?(.ended)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        card?.open?(urls)
        return true
    }
}

private struct CardView: View {
    @ObservedObject fileprivate var model: ArchiveDropCard.Model

    var body: some View {
        let active = model.isActive
        HStack(spacing: 8) {
            Image(systemName: model.createsArchive ? "doc.badge.plus" : "macwindow.badge.plus")
                .font(.system(size: 17, weight: .light))
            Text(model.createsArchive ? String(localized: .archiveCreateNewArchive) : String(localized: .commonOpen))
                .font(.callout.weight(.medium))
        }
        .foregroundStyle(Color.primary.opacity(active ? 0.85 : 0.5))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(active ? 0.07 : 0.02))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(active ? 0.42 : 0.14), lineWidth: 1.5)
        )
        .padding(6)
        .animation(.easeOut(duration: 0.12), value: active)
    }
}

/// Tells the window that a file dragged over a part of it came in, left, or
/// that the drag is over: the card over the toolbar shows meanwhile.
private struct FileDragOverWindowKey: EnvironmentKey {
    static let defaultValue: @MainActor (ArchiveFileDrag) -> Void = { _ in }
}

extension EnvironmentValues {
    var fileDragOverWindow: @MainActor (ArchiveFileDrag) -> Void {
        get { self[FileDragOverWindowKey.self] }
        set { self[FileDragOverWindowKey.self] = newValue }
    }
}
