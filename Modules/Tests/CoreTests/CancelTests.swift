//
//  CancelTests.swift
//  Modules
//
//  The status bar's Cancel while something other than the archive's own load
//  runs (#251 G6): it ended in a reset, which empties the window.
//

import Combine
import Foundation
import Testing
@testable import Core

extension AllCoreTests {

    @MainActor struct CancelTests {

        private func openZip(in dir: URL) async throws -> (ArchiveState, URL) {
            let source = dir.appendingPathComponent("source")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try Data("inside".utf8).write(to: source.appendingPathComponent("inside.txt"))
            try run("/usr/bin/zip", ["inner.zip", "inside.txt"], cwd: source)
            try Data("top".utf8).write(to: source.appendingPathComponent("top.txt"))
            let outer = dir.appendingPathComponent("outer.zip")
            try run("/usr/bin/zip", [outer.path, "inner.zip", "top.txt"], cwd: source)
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.open(url: outer)
            try await state.openTask?.value
            return (state, outer)
        }

        /// #251 G6. Cancel while a save runs leaves the window as it is, and
        /// the save goes through: there is nothing to cancel in it. It emptied
        /// the window until the save, still writing, read the archive anew.
        @Test func cancelDuringASaveLeavesTheWindowAlone() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let (state, outer) = try await openZip(in: dir)
            let added = dir.appendingPathComponent("added.txt")
            try Data("added".utf8).write(to: added)
            #expect(await state.add(url: added).value)
            // each time the window is emptied: once is the save's own reading anew
            var emptied = 0
            let watch = state.$root.map { $0 == nil }.sink { empty in
                MainActor.assumeIsolated { if empty { emptied += 1 } }
            }

            let saving = try #require(state.save())
            // under way from the moment save() returns, however fast it writes
            #expect(state.isSaving)
            state.cancelCurrentOperation()
            await saving.value
            // what the cancel left for later
            for _ in 0..<20 { await Task.yield() }
            watch.cancel()

            #expect(emptied <= 1, "the window was emptied while the save went on")
            #expect(state.root != nil, "the window was emptied")
            #expect(state.url == outer)
            #expect(try systemEntries(outer).contains("added.txt"), "the save did not go through")
        }

        /// #251 G6. Cancel while an archive inside is listed, past its
        /// unpacking, leaves it closed, and it opens again later. The listing
        /// went on, and it opened all the same.
        @Test func cancelWhileAnArchiveInsideIsListedLeavesItClosed() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let source = dir.appendingPathComponent("source")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            _ = try copyOfFixture("password", "7z_encrypted_header.7z", in: source)
            let outer = dir.appendingPathComponent("outer.zip")
            try run("/usr/bin/zip", [outer.path, "7z_encrypted_header.7z"], cwd: source)
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.open(url: outer)
            try await state.openTask?.value
            let inner = try #require(state.childItems?.first { $0.name == "7z_encrypted_header.7z" })
            // its listing asks for its password: Cancel is clicked meanwhile
            state.passwordProvider = { _ in
                await MainActor.run { state.cancelCurrentOperation() }
                return "password"
            }

            _ = try? await state.openInPlace(item: inner)

            #expect(inner.children == nil, "opened though it was cancelled")
            #expect(state.error == nil, "an alert for a cancel")
            #expect(state.url == outer)
            state.passwordProvider = { _ in "password" }
            try await state.openInPlace(item: inner)
            #expect(inner.children != nil, "it doesn't open again")
        }

        /// #251 G6. Cancel while an archive inside is being unpacked in place
        /// stops the unpacking and leaves the window as it is.
        @Test func cancelWhileAnArchiveInsideUnpacksLeavesTheWindowAlone() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let (state, outer) = try await openZip(in: dir)
            let inner = try #require(state.childItems?.first { $0.name == "inner.zip" })

            // clicked while it unpacks, as soon as the spinner shows
            var clicked = false
            let busy = state.$isBusy.dropFirst().filter { $0 }.sink { _ in
                MainActor.assumeIsolated {
                    guard !clicked else { return }
                    clicked = true
                    state.cancelCurrentOperation()
                }
            }
            _ = try? await state.openInPlace(item: inner)
            busy.cancel()
            #expect(clicked, "the unpacking never began")
            try await Task.sleep(for: .milliseconds(200))

            #expect(state.root != nil, "the window was emptied")
            #expect(state.url == outer)
            #expect(state.childItems?.contains { $0.name == "top.txt" } == true)
        }
    }
}
