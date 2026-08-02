//
//  RecentArchives.swift
//  MacPacker
//
//  The recently opened archives listed on the home screen. The list is kept here
//  rather than read back from NSDocumentController: `recentDocumentURLs` answers
//  from LaunchServices and doesn't include what was just noted, so a window
//  opened right after an archive would show a stale list. The document
//  controller is still told, for the Dock's Recent Documents menu.
//
//  The security-scoped bookmark is what makes reopening one work in a *later*
//  launch: a url that arrived by drag, open panel or Open With only grants
//  access for this run.
//

import AppKit
import Core

@MainActor
enum RecentArchives {
    private static let key = "recentArchives"
    private static let limit = 10

    /// Remember `url`. Call it while access to the file is still granted — right
    /// after the open, not later.
    static func note(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        // ponytail: one bookmark per opened archive, never evicted. A few KB in
        // UserDefaults; add pruning if that ever grows into a problem.
        Sandbox.storeBookmark(url: url)

        var list = UserDefaults.standard.stringArray(forKey: key) ?? []
        list.removeAll { $0 == url.absoluteString }
        list.insert(url.absoluteString, at: 0)
        UserDefaults.standard.set(Array(list.prefix(limit)), forKey: key)
    }

    /// Most recent first. Entries whose file is gone are kept — opening one then
    /// fails with the normal "Could not open archive" alert.
    static var urls: [URL] {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap { URL(string: $0) }
    }

    /// Empties the list (the start page's "Clear"). The stored bookmarks stay —
    /// they're the file-access grants, not the list.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        NSDocumentController.shared.clearRecentDocuments(nil)
    }
}
