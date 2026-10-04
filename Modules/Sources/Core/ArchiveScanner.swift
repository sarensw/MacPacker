//
//  ArchiveScanner.swift
//  Modules
//
//  What is about to be added, read from disk: every file and folder below the
//  ones picked, in the order the archive gets them.
//

import Foundation
import Swift7zip
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "archive")

/// What a scan found.
struct ArchiveScan: Sendable {
    struct Entry: Sendable {
        /// What the window shows for it. Below the top it is already attached to
        /// the folder it is in.
        let item: ArchiveItem
        /// What a save writes for it.
        let update: ArchiveUpdateItem
        /// Where in `entries` the folder it is in sits; `nil` for what was picked
        /// itself.
        let parent: Int?
    }

    /// A folder comes before everything in it.
    var entries: [Entry] = []
    /// Why a folder was left out, and with it all it holds; `nil` when
    /// everything could be read.
    var unreadable: String?
}

/// Off the main actor, like the loader, the extractor and the saver: a folder
/// can hold any number of files, and each one is a trip to the disk. Read on the
/// main actor, a project of 20,000 files kept the app from drawing for 11
/// seconds (#278).
final actor ArchiveScanner {

    /// - Parameters:
    ///   - urls: the files and folders picked
    ///   - base: where they go in the archive: empty for its top, else the
    ///     folder's path with a trailing slash
    ///   - cancel: looked at before each folder is read
    /// - Throws: `CancellationError` once `cancel` is set.
    func scan(_ urls: [URL], under base: String, cancel: ExtractionCancelFlag) async throws -> ArchiveScan {
        try await runBlocking {
            var scan = ArchiveScan()
            for url in urls {
                let status = Self.status(of: url)
                let archivePath = base + url.lastPathComponent
                if status?.isFolder == true {
                    // Reading a folder needs a stored grant's scope held: unlike
                    // a drop or a panel, a grant reused from storage gives no
                    // access outside it (#278). Only a folder: what there is to
                    // know about a file is readable without, and looking the
                    // grant up is a trip to another process for each one.
                    try Sandbox.accessSync(url: url) {
                        try Self.read(url, status, as: archivePath, in: nil, into: &scan, cancel: cancel)
                    }
                } else {
                    try Self.read(url, status, as: archivePath, in: nil, into: &scan, cancel: cancel)
                }
            }
            return scan
        }
    }

    /// All there is to know about `url`, in one call; `nil` when it can't be
    /// read. `lstat`: a link is an entry of its own, whatever it points at.
    private static func status(of url: URL) -> stat? {
        var status = stat()
        return lstat(url.path, &status) == 0 ? status : nil
    }

    private static func read(
        _ url: URL,
        _ status: stat?,
        as archivePath: String,
        in parent: Int?,
        into scan: inout ArchiveScan,
        cancel: ExtractionCancelFlag
    ) throws {
        let isFolder = status?.isFolder == true

        var contents: [URL] = []
        if isFolder {
            guard !cancel.isCancelled else { throw CancellationError() }
            // Read before the folder goes in: one that can't be read must not be
            // added empty, which would silently drop what it holds on save. It
            // is left out, and the reason kept.
            do {
                contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            } catch {
                log.error("Failed to read folder for add — skipping", context: [
                    "path": url.path,
                    "error": String(describing: error)
                ])
                scan.unreadable = error.localizedDescription
                return
            }
        }

        let item = ArchiveItem(
            name: url.lastPathComponent,
            virtualPath: archivePath,
            type: isFolder ? .directory : .file,
            parent: parent.map { scan.entries[$0].item.id },
            uncompressedSize: status.map { Int($0.st_size) },
            // summed the way Foundation does it, so the date is the very one
            // `attributesOfItem` gives
            modificationDate: status.map {
                Date(timeIntervalSinceReferenceDate: TimeInterval($0.st_mtimespec.tv_sec)
                    - Date.timeIntervalBetween1970AndReferenceDate
                    + 1.0e-9 * TimeInterval($0.st_mtimespec.tv_nsec))
            },
            posixPermissions: status.map { Int($0.st_mode & ~S_IFMT) })
        if let parent {
            scan.entries[parent].item.addChild(item.id)
        }
        let position = scan.entries.count
        scan.entries.append(.init(
            item: item,
            // The folder's own URL travels with its entry: a custom folder icon
            // is a flag on the folder itself, not only the hidden file inside it.
            update: isFolder
                ? .addDirectory(archivePath: archivePath, diskPath: url)
                : .addFile(archivePath: archivePath, diskPath: url),
            parent: parent))

        let named = contents.map { (name: $0.lastPathComponent, url: $0) }.sorted { $0.name < $1.name }
        for child in named {
            try read(
                child.url, Self.status(of: child.url),
                as: archivePath + "/" + child.name, in: position, into: &scan, cancel: cancel)
        }
    }
}

private extension stat {
    var isFolder: Bool { st_mode & S_IFMT == S_IFDIR }
}
