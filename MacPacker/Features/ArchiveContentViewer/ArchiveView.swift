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
import UniformTypeIdentifiers
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "archive")

/// Where a dragged file lands. Which zones exist depends on the window: an empty
/// one only opens, a read-only archive only opens, an editable archive offers both.
enum ArchiveDropZone: Equatable {
    case add
    case open

    var name: String { self == .add ? "add" : "open" }
}

struct ArchiveView: View {
    @Environment(\.openArchiveInNewWindow) private var openArchiveInNewWindow
    @EnvironmentObject private var state: ArchiveState

    @AppStorage(Keys.showColumnCompressedSize) var showCompressedSize: Bool = true
    @AppStorage(Keys.showColumnUncompressedSize) var showUncompressedSize: Bool = true
    @AppStorage(Keys.showColumnModificationDate) var showModificationDate: Bool = true
    @AppStorage(Keys.showColumnPosixPermissions) var showPermissions: Bool = false
    @AppStorage(Keys.showParentRow) var showParentRow: Bool = false

    @State private var selection: IndexSet?
    /// nil while no file is over the window; otherwise the zone the pointer is in.
    @State private var activeZone: ArchiveDropZone?
    /// The file being dragged, while it is over the window. nil when it couldn't be
    /// read off the drag pasteboard (a promised file, say).
    @State private var draggedURL: URL?
    @State private var contentSize: CGSize = .zero
    /// How far the archive window's drop cards sit inside the window.
    private static let dropInset: CGFloat = 12

    /// Adding needs an archive that the format can write, and no in-flight save.
    private var canAdd: Bool {
        state.hasArchive && state.canBeEdited && !state.isSaving
    }

    /// Dropping a non-archive doesn't open anything — it starts a new archive with
    /// that file in it. Say so, rather than promising to "open" a text file. Only
    /// the extension is knowable mid-drag, so an unreadable name keeps the neutral
    /// wording.
    private var dropCreatesArchive: Bool {
        guard let draggedURL else { return false }
        return !state.looksLikeArchive(url: draggedURL)
    }

    var body: some View {
        Group {
            if state.hasArchive {
                ArchiveTableViewRepresentable(
                    selection: $selection,
                    isReloadNeeded: $state.isReloadNeeded,
                    showCompressedSizeColumn: $showCompressedSize,
                    showUncompressedSizeColumn: $showUncompressedSize,
                    showModificationDateColumn: $showModificationDate,
                    showPosixPermissionsColumn: $showPermissions
                )
            } else {
                HomeView()
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { contentSize = proxy.size }
                    .onChange(of: proxy.size) { _, size in contentSize = size }
            }
        )
        // Two visible targets beat a hidden modifier: the drag itself says what
        // will happen. One drop target decides by pointer position rather than
        // nested `onDrop`s, which a drag already in flight would never register.
        .onDrop(of: [.fileURL], delegate: ArchiveDropDelegate(
            activeZone: $activeZone,
            draggedURL: $draggedURL,
            zone: zone(at:),
            perform: handleDrop,
            window: state.name ?? "(empty)"
        ))
        .overlay {
            if let activeZone {
                dropZones(active: activeZone)
            }
        }
        // The row count changes with the setting, and the table only reloads on
        // this flag — the toggle is in another window, so nothing else nudges it.
        .onChange(of: showParentRow) { _, _ in state.isReloadNeeded = true }
        .onAppear {
            if state.openWithUrls.count > 0 {
                state.openDropped(url: state.openWithUrls[0])
            }
            #if DEBUG
            // -DropZone add|open pins the overlay for a screenshot: no drag is
            // in flight, so nothing would arm it.
            activeZone = LaunchParameters.dropZone
            #endif
        }
        .quickLookPreview($state.previewItemUrl)
    }

    // MARK: - Drop

    /// Top half adds, bottom half opens — matching the cards drawn below. With
    /// nothing to add to, the whole window opens.
    private func zone(at location: CGPoint) -> ArchiveDropZone {
        guard canAdd, contentSize.height > 0 else { return .open }
        return location.y < contentSize.height / 2 ? .add : .open
    }

    private func handleDrop(_ zone: ArchiveDropZone, _ providers: [NSItemProvider]) {
        // Capture the action and state up front (on the main actor) so the async
        // provider callbacks don't have to reach back through the view.
        let openInNewWindowAction = openArchiveInNewWindow
        let state = self.state
        log.notice("File drop performed", context: [
            "providers": "\(providers.count)",
            "zone": zone.name
        ])

        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    log.error("Drop: could not read a file URL from the dropped item")
                    return
                }
                Task { @MainActor in
                    switch zone {
                    case .add:
                        log.notice("Drop → add to current archive", context: ["file": url.lastPathComponent])
                        state.add(url: url)
                    case .open where state.hasArchive:
                        // This window is taken (and may hold unsaved edits).
                        log.notice("Drop → open in a new window", context: ["file": url.lastPathComponent])
                        openInNewWindowAction(url)
                    case .open:
                        log.notice("Drop → open in this window", context: ["file": url.lastPathComponent])
                        if state.isSupportedArchive(url: url) { RecentArchives.note(url) }
                        state.openDropped(url: url)
                    }
                }
            }
        }
    }

    // MARK: - Drop zones

    private var openZoneIcon: String {
        if dropCreatesArchive { return "doc.badge.plus" }
        // outline weights, not filled: the whole overlay is hairlines and tints now
        return state.hasArchive ? "macwindow.badge.plus" : "shippingbox"
    }

    private var openZoneTitle: String {
        if dropCreatesArchive {
            return String(localized: "Create a new archive",
                          comment: "Drop zone shown while dragging a file that isn't an archive: releasing here starts a new archive containing that file.")
        }
        return state.hasArchive
            ? String(localized: "Open in a new window",
                     comment: "Drop zone shown while dragging an archive over a window that already holds one: releasing here opens it in a new window.")
            : String(localized: "Open",
                     comment: "Drop zone shown while dragging an archive over an empty window: releasing here opens it.")
    }

    /// The two cards an archive window offers. The start page shows nothing — its
    /// compress area is its own drop target and marks itself.
    @ViewBuilder
    private func dropZones(active: ArchiveDropZone) -> some View {
        if state.hasArchive {
            mainZones(active: active)
                .padding(Self.dropInset)
                .background(.regularMaterial)
        }
    }

    @ViewBuilder
    private func mainZones(active: ArchiveDropZone) -> some View {
        VStack(spacing: 10) {
            if canAdd {
                zoneShape(
                    zone: .add, active: active,
                    icon: "plus.rectangle.on.folder",
                    title: String(
                        localized: "Add to “\(state.name ?? "")”",
                        comment: "Drop zone shown while dragging a file over an editable archive: releasing here adds the file to that archive. The placeholder is the archive's file name."
                    )
                )
            }
            zoneShape(zone: .open, active: active, icon: openZoneIcon, title: openZoneTitle)
        }
    }

    /// One card, for a window that already holds an archive.
    private func zoneShape(
        zone: ArchiveDropZone,
        active: ArchiveDropZone,
        icon: String,
        title: String
    ) -> some View {
        let isActive = active == zone
        return RoundedRectangle(cornerRadius: 12)
            .fill(Color.primary.opacity(isActive ? 0.07 : 0.02))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(isActive ? 0.42 : 0.14), lineWidth: 1.5)
            )
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: icon).font(.system(size: 30, weight: .light))
                    Text(verbatim: title).font(.callout.weight(.medium))
                }
                .foregroundStyle(Color.primary.opacity(isActive ? 0.85 : 0.45))
            }
            .animation(.easeOut(duration: 0.12), value: isActive)
    }
}

/// Tracks the pointer through the drag so the zone under it can be highlighted —
/// `onDrop(isTargeted:)` alone only reports enter/exit, not where.
private struct ArchiveDropDelegate: DropDelegate {
    @Binding var activeZone: ArchiveDropZone?
    @Binding var draggedURL: URL?
    let zone: (CGPoint) -> ArchiveDropZone
    let perform: (ArchiveDropZone, [NSItemProvider]) -> Void
    /// only for the log — which window's delegate is talking
    let window: String

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        let entered = zone(info.location)
        // `DropInfo` only hands out item providers, and loading one is async — too
        // late to label a zone. The drag pasteboard has the url right now.
        // ponytail: first file only; a multi-file drag is labelled by its first.
        draggedURL = (NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self]) as? [URL])?.first
        log.info("drop: entered", context: [
            "window": window,
            "zone": entered.name,
            "file": draggedURL?.lastPathComponent ?? "(unknown)"
        ])
        activeZone = entered
    }

    /// Only *moves* the highlight, never arms it: `dropUpdated` keeps arriving for
    /// a while after `performDrop` (and `dropExited` never comes, because the
    /// pointer doesn't leave the window), which would put the zones back on screen
    /// and leave them there. Arming is `dropEntered`'s job alone.
    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard activeZone != nil else { return DropProposal(operation: .copy) }
        let current = zone(info.location)
        if activeZone != current { activeZone = current }
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        log.info("drop: exited", context: ["window": window])
        activeZone = nil
        draggedURL = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let target = zone(info.location)
        log.info("drop: performed", context: ["window": window, "zone": target.name])
        activeZone = nil
        draggedURL = nil
        perform(target, info.itemProviders(for: [.fileURL]))
        return true
    }
}
