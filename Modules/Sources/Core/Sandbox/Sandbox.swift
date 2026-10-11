//
//  Sandbox.swift
//  Modules
//
//  Security-scoped bookmark store for the macOS App Sandbox. Persists a grant for
//  any URL (file or folder — the kind doesn't matter) and brackets access around a
//  read. Grants are recursive, so `getSecurityUrl` walks up to the nearest
//  bookmarked ancestor — one grant on e.g. ~/Downloads covers everything under it.
//
//  Ported from FileFillet's proven `Sandbox`; bookmarks are kept in UserDefaults.
//

import Foundation
import tb

private nonisolated let log = tb.Logger(subsystem: "app.MacPacker", category: "sandbox")

public nonisolated final class Sandbox: Sendable {
    private static let sandbox = Sandbox()
    private init() {}

    private static var store: UserDefaults { .standard }

    private func getBookmarkKey(url: URL) -> String {
        String(format: "bd_%1$@", url.absoluteString)
    }

    /// Persist a security-scoped bookmark for `url`. Call right after the user has
    /// granted access (e.g. from an open panel) while the grant is still active.
    public static func storeBookmark(url: URL) {
        storeBookmark(url: url, in: store)
    }

    /// `store` is where the bookmarks are kept: the app's defaults, or a test's own.
    static func storeBookmark(url: URL, in store: UserDefaults) {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            store.set(bookmarkData, forKey: sandbox.getBookmarkKey(url: url))
        } catch {
            log.error("Could not store the bookmark: \(error.localizedDescription)")
        }
    }

    /// Runs `perform`, bracketing security-scoped access when a stored bookmark (on
    /// `url` or an ancestor) covers it. Otherwise it just runs `perform`, which then
    /// relies on the ambient / entitlement grant — so it's uniform across bookmarked
    /// folders, Open-With files, and entitled folders like Downloads.
    ///
    /// `isolation: #isolation` runs the block on the *caller's* actor (rather than
    /// hopping off it), so an `@MainActor` / actor caller can touch its own state
    /// inside. Security-scope start/stop is process-wide (thread-agnostic), so the
    /// resource stays accessible for the awaited work regardless of thread.
    public static func access<T>(
        url: URL,
        isolation: isolated (any Actor)? = #isolation,
        perform: () async throws -> T
    ) async rethrows -> T {
        if let scopedURL = sandbox.getSecurityUrl(url: url),
           scopedURL.startAccessingSecurityScopedResource() {
            defer { scopedURL.stopAccessingSecurityScopedResource() }
            return try await perform()
        }
        return try await perform()
    }

    /// Synchronous twin of `access`, for callers that can't await — the type
    /// detector reads the file's magic bytes from a plain (non-async) function, and
    /// a file reached through a stored bookmark is unreadable outside the scope.
    public static func accessSync<T>(url: URL, perform: () throws -> T) rethrows -> T {
        if let scopedURL = sandbox.getSecurityUrl(url: url),
           scopedURL.startAccessingSecurityScopedResource() {
            defer { scopedURL.stopAccessingSecurityScopedResource() }
            return try perform()
        }
        return try perform()
    }

    /// Resolves the stored bookmark for `url` (or its nearest bookmarked ancestor)
    /// WITHOUT starting access. Resolving can block on an unresponsive network
    /// volume, so prefer calling this off the main thread. Returns nil when nothing
    /// is stored for the URL or any ancestor.
    public static func securityScopedURL(for url: URL) -> URL? {
        sandbox.getSecurityUrl(url: url)
    }

    static func securityScopedURL(for url: URL, in store: UserDefaults) -> URL? {
        sandbox.getSecurityUrl(url: url, in: store)
    }

    private func getSecurityUrl(url: URL, in store: UserDefaults = Sandbox.store) -> URL? {
        var securityUrl: URL? = nil
        autoreleasepool {
            var subUrl: URL = url

            while subUrl.path().count > 1 {
                let key = getBookmarkKey(url: subUrl)
                var isStale = false

                if let bookmarkData = store.data(forKey: key),
                   let resolved = grant(in: bookmarkData, storedFor: subUrl, isStale: &isStale) {
                    securityUrl = resolved

                    // A stale-but-resolvable bookmark still grants access right
                    // now; refresh it from the resolved URL so it keeps working.
                    // Network bookmarks go stale whenever the volume is
                    // unmounted/remounted. Creating the new bookmark requires the
                    // scope to be held.
                    if isStale, resolved.startAccessingSecurityScopedResource() {
                        defer { resolved.stopAccessingSecurityScopedResource() }
                        if let refreshed = try? resolved.bookmarkData(
                            options: .withSecurityScope,
                            includingResourceValuesForKeys: nil,
                            relativeTo: nil) {
                            store.set(refreshed, forKey: key)
                        }
                    }

                    return
                }

                subUrl = subUrl.deletingLastPathComponent()
            }
        }

        return securityUrl
    }

    /// What the bookmark stored for `path` gives access to — if that is still
    /// what is at `path`. Otherwise `nil`, and the search goes on further up.
    ///
    /// A bookmark follows its file. An archive that was opened has one, for the
    /// list of recent archives: moved to the Trash, it points into the Trash,
    /// and once the Trash is emptied it cannot be resolved at all. Neither is a
    /// grant for `path` any longer. Taken for one, it hid the folder's grant
    /// above it — being the first found on the way up, or by ending the search
    /// with its error — and the next archive written under that name could not
    /// be created, in a folder the user had given access to.
    private func grant(in bookmarkData: Data, storedFor path: URL, isStale: inout Bool) -> URL? {
        let resolved: URL
        do {
            resolved = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutMounting, .withoutUI],
                bookmarkDataIsStale: &isStale
            )
        } catch {
            log.error("Could not resolve bookmark data: \(error.localizedDescription)")
            return nil
        }
        guard isSameItem(resolved, path) else {
            log.notice("Bookmark has left the path it was stored for", context: ["name": path.lastPathComponent])
            return nil
        }
        return resolved
    }

    /// Whether two urls name the same file or folder. By what the file system
    /// says they are, where it says; by path where one of them is not there to
    /// ask about — which is the case this is for.
    private func isSameItem(_ one: URL, _ other: URL) -> Bool {
        func identity(_ url: URL) -> (any NSObjectProtocol)? {
            // asked afresh: a url keeps what it was last told about its file,
            // and that was before the file moved
            var url = url
            url.removeAllCachedResourceValues()
            return (try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier
        }
        if let first = identity(one), let second = identity(other) {
            return first.isEqual(second)
        }
        return one.resolvingSymlinksInPath().path == other.resolvingSymlinksInPath().path
    }
}
