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

    /// Resolves the stored bookmark for `url` (or its nearest bookmarked ancestor)
    /// WITHOUT starting access. Resolving can block on an unresponsive network
    /// volume, so prefer calling this off the main thread. Returns nil when nothing
    /// is stored for the URL or any ancestor.
    public static func securityScopedURL(for url: URL) -> URL? {
        sandbox.getSecurityUrl(url: url)
    }

    private func getSecurityUrl(url: URL) -> URL? {
        var securityUrl: URL? = nil
        autoreleasepool {
            var isStale = false
            var subUrl: URL = url

            do {
                while subUrl.path().count > 1 {
                    let key = getBookmarkKey(url: subUrl)

                    if let bookmarkData = Sandbox.store.data(forKey: key) {
                        let resolved = try URL(
                            resolvingBookmarkData: bookmarkData,
                            options: [.withSecurityScope, .withoutMounting, .withoutUI],
                            bookmarkDataIsStale: &isStale
                        )
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
                                Sandbox.store.set(refreshed, forKey: key)
                            }
                        }

                        return
                    }

                    subUrl = subUrl.deletingLastPathComponent()
                }
            } catch {
                log.error("Could not resolve bookmark data: \(error.localizedDescription)")
            }
        }

        return securityUrl
    }
}
