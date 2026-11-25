//
//  ArchiveView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 31.08.23.
//

import ArchivePreviewUI
import Foundation
import QuickLook
import Core
import SwiftUI
import UniformTypeIdentifiers
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "archive")

struct ArchiveView: View {
    @Environment(\.openArchiveInNewWindow) private var openArchiveInNewWindow
    @Environment(\.fileDragOverWindow) private var fileDragOverWindow
    @EnvironmentObject private var state: ArchiveState

    @AppStorage(Keys.showParentRow) var showParentRow: Bool = false
    @AppStorage(Keys.showHiddenFiles, store: .macPackerShared) var showHiddenFiles: Bool = false

    /// nil while no file is over the window; otherwise the zone the pointer is in.
    @State private var activeZone: ArchiveDropZone?
    /// The file being dragged, while it is over the window. nil when it couldn't be
    /// read off the drag pasteboard (a promised file, say).
    @State private var draggedURL: URL?
    /// How far the read-only archive's drop card sits inside the window.
    private static let dropInset: CGFloat = 12

    /// An archive that can be written takes a dropped file in its list, its
    /// rows deciding where (#251 G2).
    private var listTakesDrops: Bool {
        state.hasArchive && state.canBeEdited
    }

    /// Why a file can't go in where the window is, for the status bar: the
    /// archive inside that can't be changed, named as the list names it.
    private var cantAddHereHint: String {
        let shown = state.selectedItem ?? state.root
        let name = shown.flatMap(state.archiveThatCantBeChanged(down:))?.name ?? state.name ?? ""
        return String(localized: .archiveDropCantChange(name))
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
                ArchiveListView()
            } else {
                HomeView()
            }
        }
        // The rows take a file themselves; this is the rest of the list (its
        // header, its scroller), the start page, and a read-only archive.
        .onDrop(of: [.fileURL], delegate: ArchiveDropDelegate(
            activeZone: $activeZone,
            draggedURL: $draggedURL,
            zone: zone(at:),
            perform: handleDrop,
            fileDrag: fileDragOverWindow,
            sayRefused: { refused in state.dropHint = refused ? cantAddHereHint : nil },
            window: state.name ?? "(empty)"
        ))
        .overlay {
            if let activeZone {
                dropZones(active: activeZone)
            }
        }
        // The `..` row comes and goes with the setting, and the list only reloads
        // on this flag — the toggle is in another window, so nothing else nudges it.
        .onChange(of: showParentRow) { _, _ in state.isReloadNeeded = true }
        .onChange(of: showHiddenFiles) { _, show in state.showsHiddenFiles = show }
        .onAppear {
            if state.openWithUrls.count > 0 {
                state.openDropped(url: state.openWithUrls[0])
            }
            #if DEBUG
            // -DropZone add|open pins the overlay for a screenshot: no drag is
            // in flight, so nothing would arm it.
            if !listTakesDrops { activeZone = LaunchParameters.dropZone }
            #endif
        }
        #if DEBUG
        // An editable archive's: the card over the toolbar, and where the file goes.
        .onReceive(state.$canBeEdited.filter { $0 }.first()) { _ in
            guard LaunchParameters.dropZone != nil else { return }
            fileDragOverWindow(.entered)
            state.dropHint = String(localized: .commonAddToNamed(state.name ?? ""))
        }
        #endif
        .quickLookPreview($state.previewItemUrl)
    }

    // MARK: - Drop

    private func zone(at location: CGPoint) -> ArchiveDropZone {
        state.dropZoneOutsideTheRows
    }

    private func handleDrop(_ zone: ArchiveDropZone, _ providers: [NSItemProvider]) {
        // Capture the action and state up front (on the main actor) so the async
        // provider callbacks don't have to reach back through the view.
        let openInNewWindowAction = openArchiveInNewWindow
        let state = self.state
        log.notice("File drop performed", context: [
            "providers": "\(providers.count)",
            "zone": "\(zone)"
        ])

        // One drop is one add, however many files it holds. Added file by file,
        // each was read, put into the archive and shown on its own: a thousand
        // files, a thousand times over.
        if zone == .add {
            // where the drag sprang the window is where it goes: the drag's end
            // must not take the window back before the files are read
            state.endDrag(dropped: true)
            loadDroppedFileURLs(from: providers) { urls in
                log.notice("Drop → add to current archive", context: ["files": "\(urls.count)"])
                state.add(urls: urls)
            }
            return
        }

        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    log.error("Drop: could not read a file URL from the dropped item")
                    return
                }
                Task { @MainActor in
                    if state.hasArchive {
                        // This window is taken (and may hold unsaved edits).
                        log.notice("Drop → open in a new window", context: ["file": url.lastPathComponent])
                        openInNewWindowAction(url)
                    } else {
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
            return String(localized: .archiveCreateNewArchive)
        }
        return state.hasArchive
            ? String(localized: .archiveBrowseOpenInNewWindow)
            : String(localized: .commonOpen)
    }

    /// The one card of a read-only archive, over the whole window. An editable
    /// one shows none here: its rows mark where the file goes, and its card that
    /// opens is over the toolbar. The start page shows nothing either: its
    /// compress area is its own drop target and marks itself.
    @ViewBuilder
    private func dropZones(active: ArchiveDropZone) -> some View {
        if state.hasArchive, active == .open {
            zoneShape(zone: .open, active: active, icon: openZoneIcon, title: openZoneTitle)
                .padding(Self.dropInset)
                .background(.regularMaterial)
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
    /// Tells the window, whose card over the toolbar shows for an editable archive.
    let fileDrag: @MainActor (ArchiveFileDrag) -> Void
    /// Says in the status bar why the file can't go in, or stops saying it.
    let sayRefused: @MainActor (Bool) -> Void
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
            "zone": "\(entered)",
            "file": draggedURL?.lastPathComponent ?? "(unknown)"
        ])
        activeZone = entered
        if entered == .refused { sayRefused(true) }
        fileDrag(.entered)
    }

    /// Only *moves* the highlight, never arms it: `dropUpdated` keeps arriving for
    /// a while after `performDrop` (and `dropExited` never comes, because the
    /// pointer doesn't leave the window), which would put the zones back on screen
    /// and leave them there. Arming is `dropEntered`'s job alone.
    func dropUpdated(info: DropInfo) -> DropProposal? {
        let current = zone(info.location)
        if activeZone != nil, activeZone != current { activeZone = current }
        return DropProposal(operation: current == .refused ? .forbidden : .copy)
    }

    func dropExited(info: DropInfo) {
        log.info("drop: exited", context: ["window": window])
        if activeZone == .refused { sayRefused(false) }
        activeZone = nil
        draggedURL = nil
        fileDrag(.exited)
    }

    func performDrop(info: DropInfo) -> Bool {
        let target = zone(info.location)
        log.info("drop: performed", context: ["window": window, "zone": "\(target)"])
        if activeZone == .refused { sayRefused(false) }
        activeZone = nil
        draggedURL = nil
        fileDrag(.ended)
        guard target != .refused else { return false }
        perform(target, info.itemProviders(for: [.fileURL]))
        return true
    }
}
