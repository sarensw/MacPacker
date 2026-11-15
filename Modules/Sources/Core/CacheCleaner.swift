//
//  Cache.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 22.11.23.
//

import Foundation
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "cache")

/// Removes what extractions leave in the cache: an archive opened inside an
/// archive, a Quick Look preview, a drag-out. That can be tens of thousands of
/// files or several GB, so it is removed off the main actor, like the loader,
/// the extractor and the scanner do their work (#301).
public final actor CacheCleaner {
    /// `Caches/ta`, where the temporary folders are made. Each process has its
    /// own: Quick Look's is in the extension's container, which the app cannot
    /// reach. The app group's container would be shared, but Quick Look may
    /// only read it.
    public static let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(component: "ta", directoryHint: .isDirectory)
    /// This launch's temporary folders go in here. Everything else in `folder`
    /// is left from earlier launches, and can go while this one is already
    /// extracting.
    public static let launchFolder = folder.appending(component: UUID().uuidString, directoryHint: .isDirectory)

    public init() {}

    /// Removes what earlier launches left: a launch that crashed or was killed
    /// never cleaned up after itself.
    public func removeLeftovers(in folder: URL = CacheCleaner.folder, keeping launchFolder: URL = CacheCleaner.launchFolder) async {
        try? await runBlocking {
            let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            Self.removeLogged(contents.filter { $0.lastPathComponent != launchFolder.lastPathComponent })
        }
    }

    /// Removes everything in the cache, this launch's files too.
    public func removeAll(in folder: URL = CacheCleaner.folder) async {
        await remove([folder])
    }

    /// Quick Look, as it opens an archive: removes what earlier previews left,
    /// in this process and in earlier ones. Only what is there now: the
    /// preview about to load makes its folder after this.
    ///
    /// ponytail: a preview still open in another Quick Look process loses its
    /// files too; lock each launch folder if that ever shows.
    @discardableResult
    public static func removeEarlierPreviews(
        in folder: URL = CacheCleaner.folder,
        keeping launchFolder: URL = CacheCleaner.launchFolder
    ) -> Task<Void, Never> {
        let earlier = contents(of: folder).flatMap {
            // a load makes its folder in this launch's
            $0.lastPathComponent == launchFolder.lastPathComponent ? contents(of: $0) : [$0]
        }
        return Task { await CacheCleaner().remove(earlier) }
    }

    private static func contents(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    }

    /// Removes the given folders and everything in them. Two removals can run
    /// at once, quit's over a closed window's: the second finds files already
    /// gone, which `removeItem` counts as removed.
    func remove(_ urls: [URL]) async {
        try? await runBlocking { Self.removeLogged(urls) }
    }

    /// `FileManager.removeItem`, but nothing there counts as removed: there is
    /// no cache before the first extraction, and that is no error.
    static func removeItem(at url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
        }
    }

    private static func removeLogged(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let start = Date()
        for url in urls {
            do {
                try removeItem(at: url)
            } catch {
                log.error("Could not clear cache", context: ["error": error.localizedDescription])
            }
        }
        log.info("Cache cleared", context: [
            "folders": "\(urls.count)",
            "seconds": String(format: "%.3f", Date().timeIntervalSince(start))
        ])
    }
}
