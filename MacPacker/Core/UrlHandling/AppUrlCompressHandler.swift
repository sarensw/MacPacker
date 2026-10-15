//
//  AppUrlCompressHandler.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 16.07.26.
//

import AppKit
import Core
import FinderMenu
import Foundation
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "url")

/// Writes `items` into a new archive at `destination` through the same
/// add/save path the UI uses; the format follows the destination's extension.
///
/// There is no window to show it in, so it goes to the progress window: that
/// comes up once the compress takes long enough, can cancel it, and stays up
/// to say why it failed.
/// - Returns: whether the archive was written.
@MainActor
private func writeArchive(
    _ items: [URL],
    to destination: URL,
    catalog: ArchiveTypeCatalog,
    engineSelector: ArchiveEngineSelectorProtocol
) async -> Bool {
    log.notice("Compressing \(items.count) item(s) to \(destination.lastPathComponent)")
    let state = ArchiveState(catalog: catalog, engineSelector: engineSelector)
    guard await state.compress(items, to: destination, showingProgress: true) else {
        if let error = state.error {
            log.error("Compress failed", context: ["error": error])
        } else {
            log.notice("Compress cancelled", context: ["file": destination.lastPathComponent])
        }
        return false
    }
    log.notice("Compress done", context: ["file": destination.lastPathComponent])
    return true
}

/// Finder actions "Compress to <name>.zip" and ".7z", optionally with the
/// date and time in the name: creates the archive next to the selected files
/// without further questions (one folder-access prompt is unavoidable under
/// the sandbox).
class AppUrlCompressHandler: AppUrlHandler {
    private let catalog: ArchiveTypeCatalog
    private let engineSelector: ArchiveEngineSelectorProtocol

    init(catalog: ArchiveTypeCatalog, engineSelector: ArchiveEngineSelectorProtocol) {
        self.catalog = catalog
        self.engineSelector = engineSelector
    }

    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) async {
        log.notice("Compress handler: \(appUrl.files.count) file(s)", context: ["target": appUrl.target.path])

        // The archive goes in the folder the files sit in: the window's, or
        // one expanded in it, and is named after it when there are several.
        // Access to it covers reading the inputs and writing the archive; a
        // grant on the window's folder covers those expanded in it.
        let folder = appUrl.folderOfFiles
        guard await FolderAccessStore.shared.ensureAccess(forFolder: folder) else {
            log.error("No access to \(folder.lastPathComponent) — cannot compress")
            return
        }
        let ext = appUrl.format ?? "zip"
        let name = appUrl.archiveName(
            CompressDestination.name(files: appUrl.files, target: folder, ext: ext),
            extension: ext
        )
        let dest = CompressDestination.unique(named: name, in: folder)
        if await writeArchive(appUrl.files, to: dest, catalog: self.catalog, engineSelector: self.engineSelector) {
            // only where it takes no second Finder window
            let selected = appUrl.itemsToSelect([dest])
            if !selected.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(selected)
            }
        }
    }
}

/// Finder action "Compress Each Item Separately": one zip per selected item,
/// each next to its source. A grant on the window's folder covers them all.
class AppUrlCompressEachHandler: AppUrlHandler {
    private let catalog: ArchiveTypeCatalog
    private let engineSelector: ArchiveEngineSelectorProtocol

    init(catalog: ArchiveTypeCatalog, engineSelector: ArchiveEngineSelectorProtocol) {
        self.catalog = catalog
        self.engineSelector = engineSelector
    }

    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) async {
        log.notice("Compress-each handler: \(appUrl.files.count) item(s)")

        // each item's zip goes next to it: in the window's folder, or in a
        // folder expanded in it
        for folder in Set(appUrl.files.map(appUrl.folder(of:))).sorted(by: { $0.path < $1.path }) {
            guard await FolderAccessStore.shared.ensureAccess(forFolder: folder) else {
                log.error("No access to \(folder.lastPathComponent) — cannot compress")
                return
            }
        }
        var written: [URL] = []
        for item in appUrl.files {
            let folder = appUrl.folder(of: item)
            let dest = CompressDestination.unique(
                named: CompressDestination.name(files: [item], target: folder),
                in: folder
            )
            if await writeArchive([item], to: dest, catalog: self.catalog, engineSelector: self.engineSelector) {
                written.append(dest)
            }
        }
        // only where it takes no second Finder window
        let selected = appUrl.itemsToSelect(written)
        if !selected.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(selected)
        }
    }
}

/// Finder action "Compress Contents of "<folder>"": zips what is inside the
/// folder, without the folder itself, as `<folder>.zip` next to it. The grant
/// on the surrounding folder covers reading the contents too.
class AppUrlCompressContentsHandler: AppUrlHandler {
    private let catalog: ArchiveTypeCatalog
    private let engineSelector: ArchiveEngineSelectorProtocol

    init(catalog: ArchiveTypeCatalog, engineSelector: ArchiveEngineSelectorProtocol) {
        self.catalog = catalog
        self.engineSelector = engineSelector
    }

    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) async {
        guard let folder = appUrl.files.first else { return }
        log.notice("Compress-contents handler", context: ["folder": folder.lastPathComponent])

        // the zip goes next to the folder: in the window's folder, or in one
        // expanded in it
        let parent = appUrl.folder(of: folder)
        guard await FolderAccessStore.shared.ensureAccess(forFolder: parent) else {
            log.error("No access to \(parent.lastPathComponent) — cannot compress")
            return
        }
        let contents: [URL]
        do {
            // the stored grant found above gives access only inside its scope (#278)
            contents = try Sandbox.accessSync(url: folder) {
                try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            }
        } catch {
            log.error("Could not list the folder", context: ["error": error.localizedDescription])
            return
        }
        guard !contents.isEmpty else {
            log.notice("Folder is empty — nothing to compress")
            return
        }
        let dest = CompressDestination.unique(
            named: CompressDestination.name(files: [folder], target: parent),
            in: parent
        )
        if await writeArchive(contents, to: dest, catalog: self.catalog, engineSelector: self.engineSelector) {
            // only where it takes no second Finder window
            let selected = appUrl.itemsToSelect([dest])
            if !selected.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(selected)
            }
        }
    }
}

/// Finder action "Add to Archive…": opens a new-archive window pre-filled
/// with the selection; the user picks name/format/level on save.
class AppUrlAddToArchiveHandler: AppUrlHandler {

    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) async {
        log.notice("Add-to-archive handler: \(appUrl.files.count) file(s)")

        // the selected files live in the target folder — one folder grant
        // makes them readable for the later save
        guard await FolderAccessStore.shared.ensureAccess(forFolder: appUrl.target) else {
            log.error("No access to \(appUrl.target.lastPathComponent) — cannot add to archive")
            return
        }
        archiveWindowManager.openCreateArchiveWindow(with: appUrl.files)
        NSApp.activate(ignoringOtherApps: true)
    }
}
