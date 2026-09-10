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
    state.create()
    for item in items {
        state.add(url: item)
    }
    await state.save(to: destination)?.value

    if let error = state.error {
        log.error("Compress failed", context: ["error": error])
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

    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) {
        log.notice("Compress handler: \(appUrl.files.count) file(s)", context: ["target": appUrl.target.path])

        // access to the folder covers reading the inputs and writing the archive
        requestAccessToDir(for: appUrl.target) { response, grantedUrl in
            guard response == .OK, let dir = grantedUrl else {
                log.error("Sandbox access not granted for \(appUrl.target.path) — cannot compress")
                return
            }
            Task { @MainActor in
                let ext = appUrl.format ?? "zip"
                let name = appUrl.archiveName(
                    CompressDestination.name(files: appUrl.files, target: appUrl.target, ext: ext),
                    extension: ext
                )
                let dest = CompressDestination.unique(named: name, in: dir)
                if await writeArchive(appUrl.files, to: dest, catalog: self.catalog, engineSelector: self.engineSelector) {
                    NSWorkspace.shared.activateFileViewerSelecting([dest])
                }
            }
        }
    }
}

/// Finder action "Compress Each Item Separately": one zip per selected item,
/// each next to its source. One folder grant covers them all.
class AppUrlCompressEachHandler: AppUrlHandler {
    private let catalog: ArchiveTypeCatalog
    private let engineSelector: ArchiveEngineSelectorProtocol

    init(catalog: ArchiveTypeCatalog, engineSelector: ArchiveEngineSelectorProtocol) {
        self.catalog = catalog
        self.engineSelector = engineSelector
    }

    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) {
        log.notice("Compress-each handler: \(appUrl.files.count) item(s)")

        requestAccessToDir(for: appUrl.target) { response, grantedUrl in
            guard response == .OK, let dir = grantedUrl else {
                log.error("Sandbox access not granted for \(appUrl.target.path) — cannot compress")
                return
            }
            Task { @MainActor in
                var written: [URL] = []
                for item in appUrl.files {
                    let dest = CompressDestination.unique(
                        named: CompressDestination.name(files: [item], target: appUrl.target),
                        in: dir
                    )
                    if await writeArchive([item], to: dest, catalog: self.catalog, engineSelector: self.engineSelector) {
                        written.append(dest)
                    }
                }
                if !written.isEmpty {
                    NSWorkspace.shared.activateFileViewerSelecting(written)
                }
            }
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

    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) {
        guard let folder = appUrl.files.first else { return }
        log.notice("Compress-contents handler", context: ["folder": folder.lastPathComponent])

        requestAccessToDir(for: appUrl.target) { response, grantedUrl in
            guard response == .OK, let dir = grantedUrl else {
                log.error("Sandbox access not granted for \(appUrl.target.path) — cannot compress")
                return
            }
            Task { @MainActor in
                let contents: [URL]
                do {
                    contents = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                } catch {
                    log.error("Could not list the folder", context: ["error": error.localizedDescription])
                    return
                }
                guard !contents.isEmpty else {
                    log.notice("Folder is empty — nothing to compress")
                    return
                }
                let dest = CompressDestination.unique(
                    named: CompressDestination.name(files: [folder], target: appUrl.target),
                    in: dir
                )
                if await writeArchive(contents, to: dest, catalog: self.catalog, engineSelector: self.engineSelector) {
                    NSWorkspace.shared.activateFileViewerSelecting([dest])
                }
            }
        }
    }
}

/// Finder action "Add to Archive…": opens a new-archive window pre-filled
/// with the selection; the user picks name/format/level on save.
class AppUrlAddToArchiveHandler: AppUrlHandler {

    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) {
        log.notice("Add-to-archive handler: \(appUrl.files.count) file(s)")

        // the selected files live in the target folder — one folder grant
        // makes them readable for the later save
        requestAccessToDir(for: appUrl.target) { response, grantedUrl in
            guard response == .OK, grantedUrl != nil else {
                log.error("Sandbox access not granted for \(appUrl.target.path) — cannot add to archive")
                return
            }
            Task { @MainActor in
                archiveWindowManager.openCreateArchiveWindow(with: appUrl.files)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
