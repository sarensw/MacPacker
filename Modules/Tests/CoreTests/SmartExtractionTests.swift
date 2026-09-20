//
//  SmartExtractionTests.swift
//  Modules
//
//  Smart extraction (Bandizip-style): `ArchiveState.extract(to:smart:)` and
//  "Extract selected" with the whole archive selected extract into a folder
//  named after the archive unless the archive already has a single top-level
//  entry (one file, or one folder holding everything).
//
//  `smart` is the caller's decision, not a setting Core reads — the app, the
//  Finder handlers and the Quick Look extension each pass
//  `Keys.smartExtractionEnabled()`, except the "Extract to <name>" entry, which
//  passes `false` because it just created the folder it is named after.
//
//  Fixtures are zips built at test time with the system `zip` CLI — the
//  checked-in archives all have the "one folder + one file" layout and would
//  never exercise the container decision.
//

import Foundation
import Testing
@testable import Core

extension AllCoreTests {
    @MainActor struct SmartExtractionTests {

        /// Builds a zip with the given top-level entry names (files or folders)
        /// in `dir`, using the system `zip` CLI.
        private func makeZip(in dir: URL, name: String, entries: [String]) throws -> URL {
            let src = dir.appendingPathComponent("src-\(name)")
            try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
            for entry in entries {
                let path = src.appendingPathComponent(entry)
                try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
                if entry.hasSuffix("/") {
                    try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
                } else {
                    try entry.data(using: .utf8)!.write(to: path)
                }
            }
            let zip = dir.appendingPathComponent("\(name).zip")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            p.arguments = ["-r", zip.path] + entries
            p.currentDirectoryURL = src
            let out = Pipe()
            p.standardOutput = out
            p.standardError = out
            try p.run()
            p.waitUntilExit()
            let output = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            #expect(p.terminationStatus == 0, "zip failed: \(output)")
            return zip
        }

        private func newState() -> ArchiveState {
            ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
        }

        /// Opens the archive and extracts it fully to `dest` via `state.extract(to:smart:)`.
        private func extractFull(_ state: ArchiveState, _ url: URL, to dest: URL, smart: Bool = true) async throws {
            state.open(url: url)
            try await state.openTask?.value
            await withCheckedContinuation { continuation in
                state.onStatusChange = { status in
                    if status == .done { continuation.resume() }
                }
                state.extract(to: dest, smart: smart)
            }
        }

        // MARK: - Decision rule

        @Test func singleTopLevelFileStaysFlat() async throws {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }

            let zip = try makeZip(in: dir, name: "single", entries: ["a.txt"])
            let dest = dir.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

            let state = newState()
            try await extractFull(state, zip, to: dest)

            let contents = try FileManager.default.contentsOfDirectory(atPath: dest.path).sorted()
            #expect(contents == ["a.txt"], "single file stays flat, got \(contents)")
        }

        @Test func singleTopLevelFolderStaysFlat() async throws {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }

            let zip = try makeZip(in: dir, name: "bundled", entries: ["photos/", "photos/a.jpg", "photos/b.jpg"])
            let dest = dir.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

            let state = newState()
            try await extractFull(state, zip, to: dest)

            let contents = try FileManager.default.contentsOfDirectory(atPath: dest.path).sorted()
            #expect(contents == ["photos"], "single folder stays flat, got \(contents)")
        }

        @Test func scatteredFilesGetContainerFolder() async throws {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }

            let zip = try makeZip(in: dir, name: "scatter", entries: ["a.txt", "b.txt", "c.txt"])
            let dest = dir.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

            let state = newState()
            try await extractFull(state, zip, to: dest)

            let contents = try FileManager.default.contentsOfDirectory(atPath: dest.path).sorted()
            #expect(contents == ["scatter"], "scattered files go into a container, got \(contents)")
            #expect(FileManager.default.fileExists(atPath: dest.appending(path: "scatter/a.txt").path))
            #expect(FileManager.default.fileExists(atPath: dest.appending(path: "scatter/b.txt").path))
            #expect(FileManager.default.fileExists(atPath: dest.appending(path: "scatter/c.txt").path))
        }

        @Test func multipleTopLevelFoldersGetContainerFolder() async throws {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }

            let zip = try makeZip(in: dir, name: "multi", entries: ["folder1/", "folder1/a.txt", "folder2/", "folder2/b.txt"])
            let dest = dir.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

            let state = newState()
            try await extractFull(state, zip, to: dest)

            let contents = try FileManager.default.contentsOfDirectory(atPath: dest.path).sorted()
            #expect(contents == ["multi"], "multiple folders get a container, got \(contents)")
            #expect(FileManager.default.fileExists(atPath: dest.appending(path: "multi/folder1/a.txt").path))
            #expect(FileManager.default.fileExists(atPath: dest.appending(path: "multi/folder2/b.txt").path))
        }

        @Test func folderPlusFileGetContainerFolder() async throws {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }

            // The checked-in `defaultArchive.zip` layout: one folder + one file.
            let zip = try makeZip(in: dir, name: "mixed", entries: ["folder/", "folder/README.md", "hello world.txt"])
            let dest = dir.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

            let state = newState()
            try await extractFull(state, zip, to: dest)

            let contents = try FileManager.default.contentsOfDirectory(atPath: dest.path).sorted()
            #expect(contents == ["mixed"], "folder + file gets a container, got \(contents)")
            #expect(FileManager.default.fileExists(atPath: dest.appending(path: "mixed/folder/README.md").path))
            #expect(FileManager.default.fileExists(atPath: dest.appending(path: "mixed/hello world.txt").path))
        }

        // MARK: - Smart off

        @Test func smartOffExtractsFlat() async throws {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }

            let zip = try makeZip(in: dir, name: "scatter", entries: ["a.txt", "b.txt"])
            let dest = dir.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

            let state = newState()
            try await extractFull(state, zip, to: dest, smart: false)

            let contents = try FileManager.default.contentsOfDirectory(atPath: dest.path).sorted()
            #expect(contents == ["a.txt", "b.txt"], "smart off extracts flat, got \(contents)")
        }

        /// What the Finder entry `Extract to "scatter"` does: it creates
        /// `scatter/` itself and extracts into it. The smart rule must not wrap
        /// a second `scatter/` inside — the folder is already the answer.
        @Test func extractIntoAlreadyNamedFolderDoesNotNestAgain() async throws {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }

            let zip = try makeZip(in: dir, name: "scatter", entries: ["a.txt", "b.txt"])
            // the handler's own folder, named after the archive
            let dest = dir.appendingPathComponent("out/scatter")
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

            let state = newState()
            try await extractFull(state, zip, to: dest, smart: false)

            let contents = try FileManager.default.contentsOfDirectory(atPath: dest.path).sorted()
            #expect(contents == ["a.txt", "b.txt"], "no second container, got \(contents)")
            #expect(
                !FileManager.default.fileExists(atPath: dest.appending(path: "scatter").path),
                "scatter/scatter must not exist"
            )
        }

        // MARK: - The setting itself

        /// Unset means on, in every process — the Quick Look extension never
        /// runs `Keys.registerDefaults()`, so the fallback is what it reads.
        @Test func smartExtractionDefaultsToOnWhenUnset() {
            let defaults = isolatedDefaults()

            #expect(Keys.smartExtractionEnabled(in: defaults))

            defaults.set(false, forKey: Keys.smartExtraction)
            #expect(!Keys.smartExtractionEnabled(in: defaults))
        }

        // MARK: - "Extract selected" with the whole archive selected

        @Test func extractSelectedWholeArchiveGetsContainer() async throws {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }

            let zip = try makeZip(in: dir, name: "sel", entries: ["a.txt", "b.txt"])
            let dest = dir.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

            let state = newState()
            state.open(url: zip)
            try await state.openTask?.value
            let topLevel = state.entries.values.filter { $0.parent == state.root?.id && $0.type != .root }

            await withCheckedContinuation { continuation in
                state.onStatusChange = { status in
                    if status == .done { continuation.resume() }
                }
                state.extract(items: topLevel, to: dest, smart: true)
            }

            let contents = try FileManager.default.contentsOfDirectory(atPath: dest.path).sorted()
            #expect(contents == ["sel"], "whole-archive selection gets a container, got \(contents)")
        }

        @Test func extractSelectedPartialSelectionStaysFlat() async throws {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }

            let zip = try makeZip(in: dir, name: "partial", entries: ["a.txt", "b.txt"])
            let dest = dir.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

            let state = newState()
            state.open(url: zip)
            try await state.openTask?.value
            let a = try #require(state.entries.values.first { $0.name == "a.txt" && $0.parent == state.root?.id })

            await withCheckedContinuation { continuation in
                state.onStatusChange = { status in
                    if status == .done { continuation.resume() }
                }
                state.extract(items: [a], to: dest, smart: true)
            }

            let contents = try FileManager.default.contentsOfDirectory(atPath: dest.path).sorted()
            #expect(contents == ["a.txt"], "partial selection extracts flat, got \(contents)")
        }
    }
}
