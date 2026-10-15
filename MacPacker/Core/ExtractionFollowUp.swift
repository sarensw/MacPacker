//
//  ExtractionFollowUp.swift
//  MacPacker
//
//  What happens around an extraction an archive window starts: where it
//  extracts to ("Extract next to the archive", or a folder the user picks),
//  what it put there being selected in Finder when that takes no extra window,
//  and the window closing once it is done ("Close the window afterwards").
//

import AppKit
import Core
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "extract")

@MainActor
enum ExtractionFollowUp {

    /// The archive's own folder, when the window is to extract there without
    /// asking: the setting is on, the archive is a file on disk, and the folder
    /// can be written to — a grant is asked for once, as for Finder's "Extract
    /// Here". `nil` otherwise, and the caller asks where to, as it always did.
    static func folderNextTo(_ state: ArchiveState) async -> URL? {
        guard Keys.extractNextToArchiveEnabled(),
              let archive = state.url else { return nil }
        let folder = archive.deletingLastPathComponent()
        guard await FolderAccessStore.shared.ensureAccess(forFolder: folder) else {
            log.notice("No access next to the archive — asking where to extract")
            return nil
        }
        return folder
    }

    /// "Extract archive", from the toolbar or the File menu: next to the
    /// archive when the setting says so, otherwise where the user picks.
    static func extractArchiveAskingIfNeeded(_ state: ArchiveState, in window: NSWindow?) {
        guard state.root != nil else { return }
        Task {
            if let folder = await folderNextTo(state) {
                extractArchive(state, to: folder, nextToArchive: true)
            } else if let folder = await askWhereToExtract(in: window) {
                extractArchive(state, to: folder)
            }
        }
    }

    /// "Extract selected", from the toolbar, the list's menu or the File menu:
    /// the same, for the entries selected now.
    static func extractSelectedAskingIfNeeded(_ state: ArchiveState, in window: NSWindow?) {
        let items = state.selectedItems
        guard !items.isEmpty else { return }
        Task {
            if let folder = await folderNextTo(state) {
                extractItems(items, of: state, to: folder)
            } else if let folder = await askWhereToExtract(in: window) {
                extractItems(items, of: state, to: folder)
            }
        }
    }

    /// Asks for the folder to extract into, on the window when there is one.
    /// `nil` when the user cancels.
    private static func askWhereToExtract(in window: NSWindow?) async -> URL? {
        await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = String(localized: .commonExtract)
            let answered: (NSApplication.ModalResponse) -> Void = { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
            if let window {
                panel.beginSheetModal(for: window, completionHandler: answered)
            } else {
                panel.begin(completionHandler: answered)
            }
        }
    }

    /// The window's "Extract archive", to `folder`. Once it is done, what it
    /// extracted is selected in Finder when Finder has no window open
    /// (`ExtractedItems.select`), and the window closes when it was extracted
    /// next to the archive and the setting that goes with that asks for it.
    ///
    /// The extraction runs inside whatever grant covers `folder`, held until
    /// it ends — a folder next to the archive is not one the user just picked
    /// in a panel, which would carry its own access.
    static func extractArchive(_ state: ArchiveState, to folder: URL, nextToArchive: Bool = false) {
        let topLevel = state.root?.children?.compactMap { state.entries[$0]?.name } ?? []
        Task {
            let (outcome, result) = await extracting(into: folder, named: topLevel) {
                await state.extract(to: folder, smart: Keys.smartExtractionEnabled()).value
            }
            if !result.isEmpty {
                ExtractedItems.select(result)
            }
            let closesAfter = nextToArchive
                && UserDefaults.standard.bool(forKey: Keys.closeWindowAfterExtraction)
                && outcome == .done
                && !state.hasPendingChanges
            if closesAfter {
                closeWindow(showing: state)
            }
        }
    }

    /// The window's "Extract selected", to `folder`, its result then selected
    /// in Finder when Finder has no window open.
    static func extractItems(_ items: [ArchiveItem], of state: ArchiveState, to folder: URL) {
        Task {
            let (_, result) = await extracting(into: folder, named: items.map(\.name)) {
                await state.extract(items: items, to: folder, smart: Keys.smartExtractionEnabled()).value
            }
            if !result.isEmpty {
                ExtractedItems.select(result)
            }
        }
    }

    /// Runs `extraction` into `folder` inside the access that covers it, and
    /// returns how it ended and — when it is done — what it put there (see
    /// `ExtractedItems.find`): the items named `names`, or what took their place.
    static func extracting(
        into folder: URL,
        named names: [String],
        _ extraction: () async -> ExtractionJob.State
    ) async -> (ExtractionJob.State, [URL]) {
        // a folder picked in a panel carries its own access
        let picked = folder.startAccessingSecurityScopedResource()
        defer { if picked { folder.stopAccessingSecurityScopedResource() } }
        return await Sandbox.access(url: folder) {
            let before = ExtractedItems.contents(of: folder)
            let outcome = await extraction()
            guard outcome == .done else { return (outcome, []) }
            return (outcome, ExtractedItems.find(in: folder, before: before, names: names))
        }
    }

    /// The window — or tab — showing `state`.
    static func window(showing state: ArchiveState) -> NSWindow? {
        NSApp.windows.first { ($0.windowController as? ArchiveWindowController)?.archiveState === state }
    }

    /// Closes the window showing `state`: its work is done.
    static func closeWindow(showing state: ArchiveState) {
        window(showing: state)?.performClose(nil)
    }
}
