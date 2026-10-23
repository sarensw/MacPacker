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
public enum SmartExtraction {
    /// Whether the archive goes into a container folder named after it, or can
    /// stay flat.
    ///
    /// - Parameter entries: All entries of the archive, including the synthetic root.
    static func needsContainer(_ entries: [UUID: ArchiveItem]) -> Bool {
        let root = entries.values.first { $0.type == .root }
        // Top-level: linked to the synthetic root (zips after buildTree), or
        // still parentless (isTree archives like disk images, whose top-level
        // entries never link to the synthetic root).
        let topLevel = entries.values.filter {
            guard $0.type != .root else { return false }
            return $0.parent == root?.id || $0.parent == nil
        }
        return topLevel.count != 1
    }

    /// `name` while nothing in `directory` has it, otherwise the first free one
    /// of `name 2`, `name 3`, …: how Archive Utility names a second copy. A
    /// file's extension stays last (`notes 2.txt`, `archive 2.tar.gz`); a
    /// folder's name is never split at a dot.
    ///
    /// Extraction never takes a name that is taken: what is already in the
    /// destination stays as it was.
    public static func freeName(_ name: String, in directory: URL, isDirectory: Bool) -> String {
        // lstat, so that a broken symlink counts as taken too
        let isTaken = { (candidate: String) in
            (try? FileManager.default.attributesOfItem(atPath: directory.appending(component: candidate).path)) != nil
        }
        guard isTaken(name) else { return name }

        var base = (name as NSString).deletingPathExtension
        var ext = (name as NSString).pathExtension
        if (base as NSString).pathExtension.lowercased() == "tar" {
            ext = "\((base as NSString).pathExtension).\(ext)"
            base = (base as NSString).deletingPathExtension
        }
        let keepsExtension = !isDirectory && !base.isEmpty && !ext.isEmpty
        let candidate = { (counter: Int) in
            keepsExtension ? "\(base) \(counter).\(ext)" : "\(name) \(counter)"
        }
        var counter = 2
        while isTaken(candidate(counter)) {
            counter += 1
        }
        return candidate(counter)
    }
}
