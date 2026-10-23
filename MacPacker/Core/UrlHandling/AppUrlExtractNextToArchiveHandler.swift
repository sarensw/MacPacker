//
//  AppUrlExtractNextToArchiveHandler.swift
//  MacPacker
//

import AppKit
import Core
import FinderMenu
import Foundation
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "url")

/// The Quick Look preview's Extract buttons, with "Extract next to the
/// archive" on: the archive — all of it, or the entries the url names —
/// extracted next to itself, which the preview may not write to and the app
/// may; then what came out is selected in Finder.
class AppUrlExtractNextToArchiveHandler: AppUrlHandler {
    private let catalog: ArchiveTypeCatalog
    private let engineSelector: ArchiveEngineSelectorProtocol

    init(catalog: ArchiveTypeCatalog, engineSelector: ArchiveEngineSelectorProtocol) {
        self.catalog = catalog
        self.engineSelector = engineSelector
    }

    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) async {
        guard let archive = appUrl.files.first else { return }
        let target = appUrl.target
        // Any app or page can send this url: it extracts next to the archive,
        // and nowhere else.
        guard target.standardizedFileURL.path == archive.deletingLastPathComponent().standardizedFileURL.path else {
            log.error("Extract next to the archive: the target is not the archive's folder — ignored")
            return
        }
        guard await FolderAccessStore.shared.ensureAccess(forFolder: target) else {
            log.error("No access to \(target.lastPathComponent) — cannot extract here")
            return
        }

        let smart = appUrl.action.honorsSmartExtraction && Keys.smartExtractionEnabled()
        let extracted = appUrl.items.isEmpty
            ? await extractArchive(archive, into: target, smart: smart, catalog: catalog, engineSelector: engineSelector)
            : await extractEntries(appUrl.items, of: archive, into: target, smart: smart)
        if !extracted.isEmpty {
            ExtractedItems.select(extracted)
        }
    }

    /// Opens `archive`, extracts the entries at `paths` into `destination` and
    /// waits for the job to end. Returns what it added to `destination`.
    private func extractEntries(_ paths: [String], of archive: URL, into destination: URL, smart: Bool) async -> [URL] {
        let state = ArchiveState(catalog: catalog, engineSelector: engineSelector)
        state.folderAccessProvider = { await FolderAccessStore.shared.ensureAccess(forFileIn: $0) }
        state.open(url: archive)
        do {
            try await state.openTask?.value
        } catch {
            log.error("Could not open \(archive.lastPathComponent)", context: ["error": error.localizedDescription])
            return []
        }
        let wanted = Set(paths)
        let items = state.entries.values.filter { $0.virtualPath.map(wanted.contains) ?? false }
        guard !items.isEmpty else {
            log.error("Extract next to the archive: none of the entries asked for is in \(archive.lastPathComponent)")
            return []
        }

        let (_, extracted) = await ExtractionFollowUp.extracting(into: destination, named: items.map(\.name)) {
            await state.extract(items: items, to: destination, smart: smart).value
        }
        return extracted
    }
}
