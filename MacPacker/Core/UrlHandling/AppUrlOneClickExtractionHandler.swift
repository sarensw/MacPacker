import AppKit
import Core
import FinderMenu
import Foundation
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "extraction")

/// Extracts files opened through Launch Services using the user's explicit destination.
final class AppUrlOneClickExtractionHandler: AppUrlHandler {
    private let destination: OneClickExtractionDestination
    private let catalog: ArchiveTypeCatalog
    private let engineSelector: ArchiveEngineSelectorProtocol

    init(destination: OneClickExtractionDestination, catalog: ArchiveTypeCatalog,
         engineSelector: ArchiveEngineSelectorProtocol) {
        self.destination = destination
        self.catalog = catalog
        self.engineSelector = engineSelector
    }

    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) async {
        let chosenFolder: URL?
        if destination == .chooseFolder {
            guard let folder = await chooseExtractionDestination(startingIn: appUrl.target) else { return }
            Sandbox.storeBookmark(url: folder)
            chosenFolder = folder
        } else {
            chosenFolder = nil
        }

        let detector = ArchiveTypeDetector(catalog: catalog)
        var extracted: [URL] = []
        var processedArchives: Set<URL> = []
        for archive in appUrl.files {
            // Each source may be in a different folder. The grant also covers
            // sibling volumes and writing beside the archive when requested.
            guard await FolderAccessStore.shared.ensureAccess(forFileIn: archive) else { continue }
            // Selecting several volumes of a split archive still extracts the
            // archive once. Resolve after the grant so split markers are readable.
            let canonicalArchive = detector.detect(for: archive)?.split.map {
                SplitVolumeResolver.firstVolume(for: archive, split: $0)
            } ?? archive
            guard processedArchives.insert(canonicalArchive.standardizedFileURL).inserted,
                  let folder = chosenFolder ?? destination.directory(for: canonicalArchive, detector: detector)
            else { continue }

            do {
                try Sandbox.accessSync(url: folder) {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                }
            } catch {
                log.error("Could not create extraction folder", context: ["error": error.localizedDescription])
                NSApp.presentError(error)
                continue
            }

            // These destinations are explicit: Smart Extraction must not move
            // same-folder output or add another container inside a named folder.
            let output = await extractArchive(
                archive, into: folder, smart: false, preservingExistingFiles: true,
                catalog: catalog, engineSelector: engineSelector)
            if destination == .archiveFolder, !output.isEmpty {
                extracted.append(folder)
            } else {
                extracted += output
            }
        }
        if !extracted.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(extracted)
        }
    }
}
