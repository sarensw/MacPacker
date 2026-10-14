//
//  SandboxGrantTests.swift
//  Modules
//
//  Which stored grant covers a path. Bookmarks are real ones, kept in a store
//  of the test's own; whether access is then given is the sandbox's business
//  and not tested here.
//

import Testing
import Foundation
@testable import Core

extension AllCoreTests {

    struct SandboxGrantTests {

        /// Bookmarks of this test only, gone again with `discard`.
        private func makeStore() throws -> (store: UserDefaults, discard: () -> Void) {
            let suite = "SandboxGrantTests-\(UUID().uuidString)"
            let store = try #require(UserDefaults(suiteName: suite))
            return (store, { store.removePersistentDomain(forName: suite) })
        }

        /// Where a lookup ended up, comparable with a path the test made.
        private func place(_ url: URL?) -> String? {
            url?.resolvingSymlinksInPath().path
        }

        /// A bookmark follows its file. An archive that was opened once has one,
        /// for the list of recent archives; moved to the Trash, that bookmark
        /// points into the Trash, and once the Trash is emptied at nothing. Its
        /// old path is then covered by the folder's grant and by nothing else.
        ///
        /// It used to be taken for the path's grant all the same, being the first
        /// one found on the way up: access was started on a file in the Trash, or
        /// on nothing, and the archive that was to be written under the old name
        /// could not be created — "Cannot create output file", in a folder the
        /// user had given access to.
        @Test func aBookmarkThatLeftWithItsFileDoesNotStandInForTheFoldersGrant() throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let (store, discard) = try makeStore()
            defer { discard() }
            let fm = FileManager.default
            let desktop = dir.appendingPathComponent("Desktop", isDirectory: true)
            let trash = dir.appendingPathComponent("Trash", isDirectory: true)
            try fm.createDirectory(at: desktop, withIntermediateDirectories: true)
            try fm.createDirectory(at: trash, withIntermediateDirectories: true)
            let archive = desktop.appendingPathComponent("FileApex.zip")
            try Data("first".utf8).write(to: archive)

            Sandbox.storeBookmark(url: desktop, in: store)
            Sandbox.storeBookmark(url: archive, in: store)
            #expect(place(Sandbox.securityScopedURL(for: archive, in: store)) == place(archive),
                    "while the file is there, its own bookmark is the nearest")

            let trashed = trash.appendingPathComponent("FileApex.zip")
            try fm.moveItem(at: archive, to: trashed)
            #expect(place(Sandbox.securityScopedURL(for: archive, in: store)) == place(desktop),
                    "in the Trash")

            try fm.removeItem(at: trashed)
            #expect(place(Sandbox.securityScopedURL(for: archive, in: store)) == place(desktop),
                    "Trash emptied")

            // Another file under the old name. A bookmark whose file is gone goes
            // by its path, so the old one may find this file: either way what
            // comes back is at the path again, or the folder above it.
            try Data("second".utf8).write(to: archive)
            #expect([place(archive), place(desktop)].contains(place(Sandbox.securityScopedURL(for: archive, in: store))),
                    "a new file by that name")
        }

        /// With no grant above it, such a path has none at all — and the folder
        /// is asked for again, rather than passing for covered.
        @Test func aBookmarkThatLeftWithItsFileIsNoGrantForItsOldPath() throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let (store, discard) = try makeStore()
            defer { discard() }
            let archive = dir.appendingPathComponent("FileApex.zip")
            try Data("first".utf8).write(to: archive)
            Sandbox.storeBookmark(url: archive, in: store)
            #expect(Sandbox.securityScopedURL(for: archive, in: store) != nil)

            try FileManager.default.moveItem(at: archive, to: dir.appendingPathComponent("elsewhere.zip"))
            #expect(Sandbox.securityScopedURL(for: archive, in: store) == nil)
        }
    }
}
