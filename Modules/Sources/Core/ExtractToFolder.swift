//
//  ExtractToFolder.swift
//  Modules
//
//  The folder Finder's Extract to "name" extracts an archive into.
//

import Foundation

public enum ExtractToFolder {
    /// Creates the folder `archive` is extracted into, in `target` and named
    /// after the archive. A file or folder of that name already there is left
    /// alone: the new one is "name 2".
    ///
    /// Returns `nil` when the folder cannot be created — a read-only volume, a
    /// folder the user may not write to. That is a failed job in
    /// `progressCenter` then, so the action does not end without a word.
    @MainActor
    public static func makeFolder(
        for archive: URL,
        in target: URL,
        catalog: ArchiveTypeCatalog,
        progressCenter: ExtractionProgressCenter = .shared
    ) -> URL? {
        let name = SmartExtraction.freeName(
            ArchiveTypeDetector(catalog: catalog).getNameWithoutExtension(for: archive),
            in: target, isDirectory: true)
        let folder = target.appending(component: name)
        do {
            // through the target's stored grant, which may be from an earlier
            // launch
            try Sandbox.accessSync(url: folder) {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            return folder
        } catch {
            let job = progressCenter.begin(
                archiveName: archive.lastPathComponent, destination: folder, itemCount: 0, totalBytes: nil)
            progressCenter.finish(job, .failed(error.localizedDescription))
            return nil
        }
    }
}
