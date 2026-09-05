//
//  SmartExtraction.swift
//  Modules
//
//  Created on 05.09.26.
//

import Foundation

/// Bandizip-style smart extraction: decide whether extracting an archive into
/// `destination` should go through a container folder named after the archive.
///
/// The rule (Bandizip's "Extract Here (Smart)"):
/// - exactly one top-level entry — a single file, or a single folder that holds
///   everything — is extracted as-is into the destination;
/// - anything else (several files, several folders, or files next to folders)
///   is extracted into a new folder named after the archive, so the result is
///   one tidy directory instead of files scattered across the destination.
///
/// This keeps a `foo/foo/...` double nesting away for archives that already
/// carry their own top-level folder, and keeps `a.txt, b.txt` from scattering
/// for archives that do not.
enum SmartExtraction {
    /// The container folder to create inside `destination`, or `nil` when the
    /// archive can stay flat.
    ///
    /// - Parameters:
    ///   - entries: All entries of the archive, including the synthetic root.
    ///   - archiveName: Window title of the archive — extension stripped, so a
    ///     compound `archive.tar.gz` names its folder `archive`.
    ///   - destination: Folder the user picked as extraction target.
    static func containerFolder(
        for entries: [UUID: ArchiveItem],
        archiveName: String,
        destination: URL
    ) -> URL? {
        let root = entries.values.first { $0.type == .root }
        // Top-level: linked to the synthetic root (zips after buildTree), or
        // still parentless (isTree archives like disk images, whose top-level
        // entries never link to the synthetic root).
        let topLevel = entries.values.filter {
            guard $0.type != .root else { return false }
            return $0.parent == root?.id || $0.parent == nil
        }
        let needsContainer = topLevel.count != 1
        guard needsContainer else { return nil }

        return destination.appendingPathComponent(uniqueName(for: archiveName, in: destination))
    }

    /// `name` made unique inside `directory` the way Finder does: when a folder
    /// of that name already exists, `name (2)`, `name (3)`, … is used.
    private static func uniqueName(for name: String, in directory: URL) -> String {
        let candidate = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return name }

        var counter = 2
        while FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("\(name) (\(counter))").path
        ) {
            counter += 1
        }
        return "\(name) (\(counter))"
    }
}
