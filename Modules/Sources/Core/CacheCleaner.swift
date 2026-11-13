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
    /// `Caches/ta`, where the temporary folders are made.
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
