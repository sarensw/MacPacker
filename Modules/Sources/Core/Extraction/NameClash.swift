//
//  NameClash.swift
//  Modules
//
//  What an extraction does with an item whose name is already taken where it
//  goes — a setting (General ▸ "If an item already exists").
//

import Foundation

public enum NameClash: String, CaseIterable, Sendable {
    /// The new item takes a free name beside the one already there, the way
    /// smart extraction's folder does: `photo (2).jpg`, `photos (2)`. Nothing
    /// that was there is touched.
    case keepBoth
    /// The new item takes the name: a file already there is replaced, a folder
    /// already there is extracted into. What is replaced is deleted.
    case replace
    /// As `replace`, but a file that is replaced goes to the Trash.
    case replaceToTrash

    /// The setting, from the app group, where the Quick Look preview reads it
    /// too. Unset is `keepBoth`: nothing is lost unless the user says so.
    public static func current(in defaults: UserDefaults = .macPackerShared) -> NameClash {
        defaults.string(forKey: Keys.nameClash).flatMap(Self.init(rawValue:)) ?? .keepBoth
    }

    /// A folder's name, made free in `folder` (see below).
    public static func freeName(for name: String, in folder: URL) -> String {
        freeName(for: name, in: folder, isFolder: true)
    }

    /// `name`, or the first of `name (2)`, `name (3)`, … that nothing in
    /// `folder` has and `reserved` does not hold — a file's number goes before
    /// its extension. Taken means anything of that name, a broken link too.
    static func freeName(for name: String, in folder: URL, isFolder: Bool, reserved: Set<String> = []) -> String {
        func isTaken(_ candidate: String) -> Bool {
            reserved.contains(candidate)
                || (try? FileManager.default.attributesOfItem(
                    atPath: folder.appendingPathComponent(candidate).path)) != nil
        }
        guard isTaken(name) else { return name }

        let ext = isFolder ? "" : (name as NSString).pathExtension
        let base = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        var counter = 2
        while true {
            let candidate = "\(base) (\(counter))" + (ext.isEmpty ? "" : ".\(ext)")
            if !isTaken(candidate) { return candidate }
            counter += 1
        }
    }
}
