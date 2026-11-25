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
        /// the save goes through: there is nothing to cancel in it.
        @Test func cancelDuringASaveLeavesTheWindowAlone() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let (state, outer) = try await openZip(in: dir)
            // big and random enough that the save is still writing when the
            // cancel has done its work
            let added = dir.appendingPathComponent("added.bin")
            var bytes = [UInt8](repeating: 0, count: 20_000_000)
            for i in stride(from: 0, to: bytes.count, by: 8) { bytes[i] = UInt8.random(in: 0...255) }
            try Data(bytes).write(to: added)
            #expect(await state.add(url: added).value)

            let saving = try #require(state.save())
            try await Task.sleep(for: .milliseconds(50))
            state.cancelCurrentOperation()
            try await Task.sleep(for: .milliseconds(500))
            #expect(state.isSaving, "the save was over too soon to tell")
            #expect(state.root != nil, "the window was emptied while the save went on")
            await saving.value
            try await Task.sleep(for: .milliseconds(200))

            #expect(state.root != nil, "the window was emptied")
            #expect(state.url == outer)
            #expect(try systemEntries(outer).contains("added.bin"), "the save did not go through")
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
