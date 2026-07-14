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
#if DEBUG
import SandboxPilotKit
#endif

/// Opens MacPacker into a specific state from launch parameters — another way
/// to open an archive, alongside Finder's "Open With…" and the `app.macpacker://`
/// URL scheme. A script, the `open` command, or an automation harness can launch
/// MacPacker straight to a file inside an archive:
///
///   -ArchivePath  <path>    open this archive in a window
///   -NavigatePath a/b/c     navigate into these folder / nested-archive segments, in order
///   -SelectItem   <name>    select this item in the final folder
///
/// This is a normal, shipping feature — not gated to debug builds. It also
/// encapsulates *where a parameter comes from*: it resolves each one from two
/// sources, in priority order —
///   1. a real command-line launch argument (`open -a MacPacker --args …`), read
///      from the argument domain only (transient, never a persisted preference);
///   2. a value SandboxPilot set (DEBUG builds only), read from the Kit's
///      dedicated suite — a fallback used only when there's no real argument.
/// Genuine command-line launches always win, and from `value(_:)` onward the
/// rest of the app is source-agnostic.
@MainActor
enum LaunchParameters {
    static let archivePathKey = "ArchivePath"
    static let navigatePathKey = "NavigatePath"
    static let selectItemKey = "SelectItem"
    static let extractDemoKey = "ExtractDemo"
    static let disableUpdateChecksKey = "DisableUpdateChecks"

    /// Resolves a launch parameter from its two sources (command line first,
    /// then SandboxPilot in debug builds).
    static func value(_ key: String) -> String? {
        if let real = UserDefaults.standard.launchArgument(key) { return real }
        #if DEBUG
        if let fromPilot = SandboxPilot.launchParameter(key) { return fromPilot }
        #endif
        return nil
    }

    /// Boolean form — true for "1" / "YES" / "true".
    static func flag(_ key: String) -> Bool {
        (value(key) as NSString?)?.boolValue ?? false
    }

    static var archivePath: String? { value(archivePathKey) }

    /// True when launch parameters ask MacPacker to open a specific archive.
    /// The app then shows that archive's window instead of an empty/welcome one.
    static var opensArchive: Bool { archivePath != nil }

    /// True when launch parameters request the extraction preview (debug).
    static var isExtractDemo: Bool { flag(extractDemoKey) }

    /// True when launch parameters ask to skip the startup update check.
    static var disableUpdateChecks: Bool { flag(disableUpdateChecksKey) }

    /// Opens the requested archive (if any), navigates to the requested path,
    /// and selects the requested item.
    static func applyIfNeeded(windowManager: ArchiveWindowManager) {
        guard let archivePath else { return }
        let url = URL(fileURLWithPath: archivePath)
        let navigate = value(navigatePathKey)
        let select = value(selectItemKey)

        // A plain -ArchivePath just opens the archive; only bind the state and
        // drive it when a navigation or selection was actually requested.
        guard navigate != nil || select != nil else {
            windowManager.openArchiveWindow(for: url)
            return
        }
        let state = windowManager.openArchiveWindow(for: url)
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
