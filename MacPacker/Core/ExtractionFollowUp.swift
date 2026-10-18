//
//  ExtractionFollowUp.swift
//  MacPacker
//
//  What happens around an extraction an archive window starts: where it
//  extracts to ("Extract next to the archive", or a folder the user picks),
//  what it put there being selected in Finder when that takes no extra window,
//  and what becomes of the archive and its window once it is done ("Move to
//  Trash after extraction", "Close the window afterwards"). Finder's actions
//  use the Trash part too.
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
    /// (`ExtractedItems.select`); the archive goes to the Trash when the
    /// setting asks for it; and the window closes — when the archive went, or
    /// when it was extracted next to itself and the setting that goes with
    /// that asks for it.
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
            let trashed = await trashIfAsked(state, after: outcome)
            if !result.isEmpty {
                ExtractedItems.select(result)
            }
            let closesAfter = nextToArchive
                && UserDefaults.standard.bool(forKey: Keys.closeWindowAfterExtraction)
                && outcome == .done
                && !state.hasPendingChanges
                && !state.isAddingItems
            if trashed || closesAfter {
                closeWindow(showing: state)
            }
        }
    }

    /// The window's "Extract selected", to `folder`, its result then selected
    /// in Finder when Finder has no window open. Only part of the archive, so
    /// it never goes to the Trash.
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

    /// Moves the archive to the Trash after an extraction of all of it, when
    /// the setting asks for it: only once that extraction has finished, never
    /// after one that was cancelled or failed, and never while the window holds
    /// edits not yet saved into the archive, or files still being added to it.
    /// Every volume of a split archive goes. Returns whether the archive's own
    /// file went.
    @discardableResult
    static func trashIfAsked(_ state: ArchiveState, after outcome: ExtractionJob.State) async -> Bool {
        guard UserDefaults.standard.bool(forKey: Keys.trashArchiveAfterExtraction),
              outcome == .done,
              !state.hasPendingChanges,
              !state.isAddingItems,
              let archive = state.url else { return false }
        // Moving a file out of its folder is a change to that folder.
        guard await FolderAccessStore.shared.ensureAccess(forFileIn: archive) else {
            log.notice("No access to the archive's folder — it stays where it is")
            return false
        }
        let files = state.filesOnDisk()
        return await Sandbox.access(url: archive.deletingLastPathComponent()) {
            // The archive's own file comes first. If it cannot go, nothing does:
            // its other volumes alone would be good for nothing in the Trash.
            for (index, file) in files.enumerated() {
                do {
                    try FileManager.default.trashItem(at: file, resultingItemURL: nil)
                    log.notice("Moved the extracted archive to the Trash", context: ["file": file.lastPathComponent])
                } catch {
                    log.error("Could not move \(file.lastPathComponent) to the Trash", context: ["error": error.localizedDescription])
                    if index == 0 { return false }
                }
            }
            return !files.isEmpty
        }
    }

    /// The window — or tab — showing `state`.
    static func window(showing state: ArchiveState) -> NSWindow? {
        NSApp.windows.first { ($0.windowController as? ArchiveWindowController)?.archiveState === state }
    }

    /// Closes the window showing `state`: its work is done, or what it showed
    /// is in the Trash now.
    static func closeWindow(showing state: ArchiveState) {
        window(showing: state)?.performClose(nil)
    }
}
