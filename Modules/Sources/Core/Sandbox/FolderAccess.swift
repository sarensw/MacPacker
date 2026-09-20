//
//  FolderAccess.swift
//  Modules
//
//  What a folder grant has to cover, and whether one has to be asked for. Paths
//  only — no disk, no panel — so the app has one decision to act on and one
//  place where the rule is tested. Acquiring the grant is the app's job
//  (`FolderAccessStore`), holding it is `Sandbox`'s.
//

import Foundation

public enum FolderAccess {
    /// What is needed before reading or writing at a url.
    public enum Decision: Equatable {
        /// A stored bookmark on the folder or an ancestor already covers it.
        case covered
        /// Under ~/Downloads: the `files.downloads.read-write` entitlement covers
        /// it, at most a one-click system prompt. The folder to touch to find out.
        case downloads(URL)
        /// Nothing covers it — ask for this folder.
        case prompt(URL)
    }

    /// The folder a grant has to cover for `url`: the file's own folder, or the
    /// folder itself. Always a directory url, so two names for the same folder
    /// compare equal.
    public static func folder(for url: URL, isDirectory: Bool) -> URL {
        let folder = isDirectory ? url : url.deletingLastPathComponent()
        return URL(fileURLWithPath: folder.path, isDirectory: true)
    }

    /// Whether `url` is `ancestor` or lies somewhere inside it.
    public static func isInside(_ url: URL, _ ancestor: URL) -> Bool {
        let u = url.standardizedFileURL.path
        let a = ancestor.standardizedFileURL.path
        return u == a || u.hasPrefix(a + "/")
    }

    /// Cheapest first: a stored grant, then the Downloads entitlement, then a panel.
    ///
    /// `isCovered` is asked about the *folder*, never the file: the recents list
    /// bookmarks each archive file, and that grant reads the file alone — writing
    /// beside it, or reading a sibling volume, still needs the folder.
    public static func decide(
        for url: URL,
        isDirectory: Bool,
        downloads: URL?,
        isCovered: (URL) -> Bool
    ) -> Decision {
        let folder = folder(for: url, isDirectory: isDirectory)
        if isCovered(folder) { return .covered }
        if let downloads, isInside(folder, downloads) { return .downloads(downloads) }
        return .prompt(folder)
    }
}
