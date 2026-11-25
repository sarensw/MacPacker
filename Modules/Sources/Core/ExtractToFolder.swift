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
        let name = ArchiveTypeDetector(catalog: catalog).getNameWithoutExtension(for: archive)
        do {
            // through the target's stored grant, which may be from an earlier
            // launch; the free name is looked for in there too: outside it,
            // what is already there may not be seen, and the extraction would
            // go into the folder of that name
            return try Sandbox.accessSync(url: target) {
                let folder = target.appending(component: SmartExtraction.freeName(name, in: target, isDirectory: true))
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                return folder
            }
        } catch {
            let job = progressCenter.begin(
                archiveName: archive.lastPathComponent, destination: target.appending(component: name),
                itemCount: 0, totalBytes: nil)
            progressCenter.finish(job, .failed(error.localizedDescription))
            return nil
        }
    }
}
