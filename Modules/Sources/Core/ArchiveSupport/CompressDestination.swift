//
//  CompressDestination.swift
//  Modules
//
//  Where a "compress these files" action puts its archive, and what it calls it.
//  Shared by the Finder "Compress to …" action, its menu label (the Finder
//  extension builds the name the same way) and the drop window — one rule, so a
//  drop and a right-click on the same selection produce the same file.
//

import Foundation

public enum CompressDestination {

    /// The archive name for a selection: one item → its own stem, several → the
    /// folder they sit in. `ext` is the format extension without a dot ("zip", "7z").
    public static func name(files: [URL], target: URL, ext: String = "zip") -> String {
        if files.count == 1, let only = files.first {
            return only.deletingPathExtension().lastPathComponent + "." + ext
        }
        return target.lastPathComponent + "." + ext
    }

    /// First non-existing variant of `name` in `dir`: "x.zip", "x 2.zip", "x 3.zip", …
    /// Never overwrites — a repeated drop of the same selection makes a new file.
    public static func unique(named name: String, in dir: URL) -> URL {
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = dir.appendingPathComponent(name)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(stem) \(counter).\(ext)")
            counter += 1
        }
        return candidate
    }
}
