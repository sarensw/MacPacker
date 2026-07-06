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

struct ArchiveView: View {
    @Environment(\.openWindow) var openWindow
    @Environment(\.openArchiveInNewWindow) private var openArchiveInNewWindow
    @EnvironmentObject private var state: ArchiveState

    @AppStorage(Keys.showColumnCompressedSize) var showCompressedSize: Bool = true
    @AppStorage(Keys.showColumnUncompressedSize) var showUncompressedSize: Bool = true
    @AppStorage(Keys.showColumnModificationDate) var showModificationDate: Bool = true
    @AppStorage(Keys.showColumnPosixPermissions) var showPermissions: Bool = false

    @State private var selection: IndexSet?
    @State private var loading: Bool = false
    @State private var isDropTargeted = false
    @State private var hintTimer: Timer?

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
        // Plain drop = add (or open, when nothing is loaded / it can't be edited).
        // ⌥ drop = open in a new window. `isDropTargeted` (SwiftUI-managed) reliably
        // brackets the drag, so the status-bar hint always clears when it ends.
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .onChange(of: isDropTargeted) { _, targeted in
            if targeted { startHintPolling() } else { stopHintPolling() }
        }
        .onDisappear { stopHintPolling() }
        .onAppear {
            if state.openWithUrls.count > 0 {
                state.openDropped(url: state.openWithUrls[0])
            }
        }
        .quickLookPreview($state.previewItemUrl)
    }

    // MARK: - Drop

    /// Plain drop adds to the current editable archive (or opens it, if nothing is
    /// loaded / it can't be edited). ⌥ drop opens the file in a new window. ⌥ is
    /// used rather than ⌘ because a Finder ⌘-drag means "move" — a copy target would
    /// reject it (what looked like "nothing happens"), and accepting a move risks
    /// deleting the source file. ⌥ maps cleanly to copy.
    private func handleDrop(_ providers: [NSItemProvider]) {
        let flags = NSEvent.modifierFlags
        let openInNewWindow = flags.contains(.option)
        // Capture the "open in new window" action and state up front (on the main
        // actor) so the async provider callbacks don't have to reach back through
        // the view.
        let openInNewWindowAction = openArchiveInNewWindow
        let state = self.state
        log.notice("File drop performed", context: [
            "providers": "\(providers.count)",
            "option": "\(flags.contains(.option))",
            "command": "\(flags.contains(.command))"
        ])
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    log.error("Drop: could not read a file URL from the dropped item")
                    return
                }
                Task { @MainActor in
                    if openInNewWindow {
                        log.notice("Drop → open in a new window", context: ["file": url.lastPathComponent])
                        openInNewWindowAction(url)
                    } else if state.hasArchive, state.canBeEdited {
                        log.notice("Drop → add to current archive", context: ["file": url.lastPathComponent])
                        state.add(url: url)
                    } else {
                        log.notice("Drop → open in this window", context: ["file": url.lastPathComponent])
                        state.openDropped(url: url)
                    }
                }
            }
        }
    }

    // MARK: - Status-bar hint

    /// While a file is over the window, poll ⌥ so the status-bar hint can flip
    /// between "add" and "open in a new window". A timer (not `dropUpdated`) is used
    /// so the flip tracks the key even when the pointer is still; it runs on the
    /// common run-loop mode so it keeps firing during the drag.
    private func startHintPolling() {
        stopHintPolling(clearHint: false)
        let state = self.state
        // Show the hint whenever an archive is open. The default drop differs — add
        // for an editable archive, replace for a read-only one — but ⌥ always opens a
        // new window, so the affordance is worth advertising either way. An empty
        // window just opens the dropped file, so no hint there.
        guard state.hasArchive else {
            state.dropHint = nil
            return
        }
        setHint(on: state)
        let timer = Timer(timeInterval: 0.06, repeats: true) { _ in
            MainActor.assumeIsolated { setHint(on: state) }
        }
        RunLoop.main.add(timer, forMode: .common)
        hintTimer = timer
    }

    private func stopHintPolling(clearHint: Bool = true) {
        hintTimer?.invalidate()
        hintTimer = nil
        if clearHint { state.dropHint = nil }
    }
}

/// Free function (no `self` capture) so it's safe to call from the polling timer.
@MainActor
private func setHint(on state: ArchiveState) {
    let hint: ArchiveDropHint = NSEvent.modifierFlags.contains(.option) ? .openInNewWindow : .dragging
    if state.dropHint != hint { state.dropHint = hint }
}
