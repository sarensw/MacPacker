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
///   -SearchQuery  <text>    filter the listing by this text
///   -SelectItem   a,b,c     select these items in the final folder (comma-separated)
///   -NewArchive   1         open a window with a fresh, empty archive instead
///   -AddFiles     a,b,c     add these files — to the new archive, or to the
///                           opened one at the navigated-to path
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
    static let searchQueryKey = "SearchQuery"
    static let selectItemKey = "SelectItem"
    static let newArchiveKey = "NewArchive"
    static let addFilesKey = "AddFiles"
    static let extractDemoKey = "ExtractDemo"
    static let dropZoneKey = "DropZone"
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

    /// True when launch parameters ask for a fresh, empty archive to fill.
    static var createsArchive: Bool { flag(newArchiveKey) }

    /// True when launch parameters put a window on screen themselves — the app
    /// then skips the empty launch window and the welcome screen.
    static var opensWindow: Bool { opensArchive || createsArchive }

    /// True when launch parameters request the extraction preview (debug).
    static var isExtractDemo: Bool { flag(extractDemoKey) }

    #if DEBUG
    /// Screenshot-only: pins the drop-zone overlay on, so the drag-and-drop UI
    /// can be captured without a live drag (nothing simulates one).
    static var dropZone: ArchiveDropZone? {
        switch value(dropZoneKey) {
        case "add": .add
        case "open": .open
        default: nil
        }
    }
    #endif

    /// True when launch parameters ask to skip the startup update check.
    static var disableUpdateChecks: Bool { flag(disableUpdateChecksKey) }

    /// Opens the requested archive (if any), navigates to the requested path,
    /// and selects the requested item.
    static func applyIfNeeded(windowManager: ArchiveWindowManager) {
        if createsArchive {
            // The window already holds the added files; drive it for the rest,
            // so -SearchQuery and -SelectItem mean the same thing here as they
            // do for an opened archive rather than being silently dropped.
            let state = windowManager.openCreateArchiveWindow(with: filesToAdd)
            Task {
                await drive(state, navigate: nil, add: [],
                            search: value(searchQueryKey), select: value(selectItemKey))
            }
            return
        }
        guard let archivePath else { return }
        let url = resolveInputFile(archivePath)
        let navigate = value(navigatePathKey)
        let search = value(searchQueryKey)
        let select = value(selectItemKey)
        let add = filesToAdd

        // A plain -ArchivePath just opens the archive; only bind the state and
        // drive it when something was actually requested on top.
        guard navigate != nil || search != nil || select != nil || !add.isEmpty else {
            windowManager.openArchiveWindow(for: url)
            return
        }
        let state = windowManager.openArchiveWindow(for: url)
        Task { await drive(state, navigate: navigate, add: add, search: search, select: select) }
    }

    /// The `-AddFiles` list, resolved to readable urls.
    private static var filesToAdd: [URL] {
        (value(addFilesKey) ?? "")
            .split(separator: ",")
            .map { resolveInputFile($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// Resolves a file named by a launch parameter (the archive to open, or a
    /// file to put into a new one), tolerating a path this process can't read.
    ///
    /// A genuine launch (`open --args -ArchivePath /some/file.zip`) passes a path
    /// we can read, and we use it verbatim. But a sandboxed automation harness
    /// (SandboxPilot) can't stage a file into *this* app's container, so its plan
    /// may reference a test archive by a path outside our sandbox. In debug builds
    /// we then look for the same file name in the demo folder (the one location
    /// the downloads entitlement lets us read), and finally fall back to a bundled
    /// copy, so those runs still open a real archive instead of an empty window.
    private static func resolveInputFile(_ path: String) -> URL {
        if FileManager.default.isReadableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        #if DEBUG
        let filename = (path as NSString).lastPathComponent
        if let staged = demoFile(named: filename) {
            log.info("Launch parameter file not readable (\(path)); using staged demo file")
            return staged
        }
        if let bundled = bundledArchive(named: filename) {
            log.info("Launch parameter archive not readable (\(path)); using bundled fallback")
            return bundled
        }
        #endif
        return URL(fileURLWithPath: path)   // let the loader surface the failure
    }

    #if DEBUG
    /// `~/Downloads/MacPacker-Demo/[extra/]<name>` — the screenshot archives and
    /// the loose files added to a new one, matched by basename so a plan can name
    /// them by their repo-relative path while the sandbox only ever reads them out
    /// of Downloads. Generated (not committed) by
    /// `assets/screenshots/make_demo_archives.py`.
    private static func demoFile(named filename: String) -> URL? {
        // The *real* home, not the container: `FileManager`'s downloads url is the
        // container one, and the window subtitle would show that path even though
        // the entitlement redirects it to the same file.
        guard let pw = getpwuid(getuid()) else { return nil }
        let demo = URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
            .appending(path: "Downloads/MacPacker-Demo")
        return [demo.appending(path: filename), demo.appending(path: "extra").appending(path: filename)]
            .first { FileManager.default.isReadableFile(atPath: $0.path) }
    }

    /// The debug-only test archive, embedded as a base64 blob (see
    /// `ScreenshotTestArchive`) so it's stripped from release. Materialised into
    /// this app's container tmp dir — a readable URL for the archive loader.
    /// Matched by basename so a plan's `{archive}` (e.g. `defaultArchive.zip`)
    /// resolves even though its path lies outside our sandbox.
    private static func bundledArchive(named filename: String) -> URL? {
        guard (filename as NSString).deletingPathExtension == "defaultArchive",
              let data = Data(base64Encoded: ScreenshotTestArchive.defaultArchiveBase64) else { return nil }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: dest)
            return dest
        } catch {
            log.error("Failed to materialise bundled test archive: \(error.localizedDescription)")
            return nil
        }
    }
    #endif

    /// Waits for the initial load, walks the requested path segment by segment
    /// (awaiting each nested-archive unfold), adds the requested files, applies
    /// the search filter, then selects the requested items — in that order,
    /// because files land in the folder being shown, navigating clears the
    /// search, and searching clears the selection.
    private static func drive(
        _ state: ArchiveState, navigate: String?, add: [URL], search: String?, select: String?
    ) async {
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

        for file in add {
            state.add(url: file)
        }

        if let search, !search.isEmpty {
            state.search(search)
        }

        if let select, !select.isEmpty {
            let names = select.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let items = names.compactMap { name in state.childItems?.first { $0.name == name } }
            if items.count != names.count {
                log.error("Launch parameter select item(s) not found: \(select)")
            }
            if !items.isEmpty {
                state.selectedItems = items
                state.isReloadNeeded = true
            }
        }
    }
}

private let log = tb.Logger(subsystem: "app.MacPacker", category: "launch")
