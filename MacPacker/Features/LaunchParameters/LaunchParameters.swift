//
//  LaunchParameters.swift
//  MacPacker
//
//  Created by Claude on 13.07.26.
//

import AppKit
import Core
import Foundation
import tb

/// Opens MacPacker into a specific state from launch parameters — another way
/// to open an archive, alongside Finder's "Open With…" and the `app.macpacker://`
/// URL scheme. A script, the `open` command, an automation harness, or a
/// screenshot tool (SandboxPilot is the first) can launch MacPacker straight to
/// a file inside an archive:
///
///   -ArchivePath  <path>    open this archive in a window
///   -NavigatePath a/b/c     navigate into these folder / nested-archive segments, in order
///   -SelectItem   <name>    select this item in the final folder
///
/// The parameters are read from `UserDefaults`, so they work both as
/// `NSArgumentDomain` command-line arguments (`open -a MacPacker --args
/// -ArchivePath …`) and as launch defaults a driver patches before relaunching.
/// This is a normal, shipping feature — not gated to debug builds. Reading an
/// arbitrary path is still subject to the sandbox: it works for locations the
/// app can reach (its container, a granted folder), the same as any file open.
@MainActor
enum LaunchParameters {
    static let archivePathKey = "ArchivePath"
    static let navigatePathKey = "NavigatePath"
    static let selectItemKey = "SelectItem"

    /// True when launch parameters ask MacPacker to open a specific archive.
    /// The app then shows that archive's window instead of an empty/welcome one.
    static var opensArchive: Bool {
        UserDefaults.standard.string(forKey: archivePathKey) != nil
    }

    /// Opens the requested archive (if any), navigates to the requested path,
    /// and selects the requested item.
    static func applyIfNeeded(windowManager: ArchiveWindowManager) {
        guard let archivePath = UserDefaults.standard.string(forKey: archivePathKey) else { return }
        let url = URL(fileURLWithPath: archivePath)
        let navigate = UserDefaults.standard.string(forKey: navigatePathKey)
        let select = UserDefaults.standard.string(forKey: selectItemKey)

        let state = windowManager.openArchiveWindow(for: url)
        // Only navigate/select when asked — a plain -ArchivePath just opens the archive.
        guard navigate != nil || select != nil else { return }
        Task { await drive(state, navigate: navigate, select: select) }
    }

    /// Waits for the initial load, walks the requested path segment by segment
    /// (awaiting each nested-archive unfold), then selects the requested item.
    private static func drive(_ state: ArchiveState, navigate: String?, select: String?) async {
        try? await state.openTask?.value

        if let navigate, !navigate.isEmpty {
            for segment in navigate.split(separator: "/").map(String.init) {
                guard let child = state.childItems?.first(where: { $0.name == segment }) else {
                    log.error("Launch parameter navigate segment not found: \(segment)")
                    break
                }
                try? await state.openAsync(item: child)
            }
        }

        if let select, !select.isEmpty {
            if let item = state.childItems?.first(where: { $0.name == select }) {
                state.selectedItems = [item]
                state.isReloadNeeded = true
            } else {
                log.error("Launch parameter select item not found: \(select)")
            }
        }
    }
}

private let log = tb.Logger(subsystem: "app.MacPacker", category: "launch")
