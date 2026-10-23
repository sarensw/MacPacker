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

/// Answers the password prompt once, wrongly, and cancels it after that.
private actor OneWrongAnswer {
    private var asked = false

    func next() -> String? {
        defer { asked = true }
        return asked ? nil : "wrong"
    }
}

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

        // MARK: - What is already there stays untouched

        private func read(_ url: URL) -> String? {
            try? String(contentsOf: url, encoding: .utf8)
        }

        /// Archive Utility's numbering: the extension stays last, a folder is
        /// not split at a dot, and a taken number is skipped.
        @Test func freeNamesNumberLikeArchiveUtility() throws {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            for name in ["notes.txt", "notes 2.txt", "README", "photos.2024", "archive.tar.gz"] {
                try "".write(to: dir.appending(path: name), atomically: true, encoding: .utf8)
            }

            #expect(SmartExtraction.freeName("new.txt", in: dir, isDirectory: false) == "new.txt")
            #expect(SmartExtraction.freeName("notes.txt", in: dir, isDirectory: false) == "notes 3.txt")
            #expect(SmartExtraction.freeName("README", in: dir, isDirectory: false) == "README 2")
            #expect(SmartExtraction.freeName("photos.2024", in: dir, isDirectory: true) == "photos.2024 2")
            #expect(SmartExtraction.freeName("archive.tar.gz", in: dir, isDirectory: false) == "archive 2.tar.gz")
        }

        /// An item whose name is taken in the destination comes out under the
        /// next free one, as Archive Utility names a second copy. Extracting
        /// used to write over the file that was there.
        @Test func aTakenNameGetsTheNextFreeOne() async throws {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }

            let zip = try makeZip(in: dir, name: "single", entries: ["a.txt"])
            let dest = dir.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            try "mine".write(to: dest.appending(path: "a.txt"), atomically: true, encoding: .utf8)

            try await extractFull(newState(), zip, to: dest)

            let contents = try FileManager.default.contentsOfDirectory(atPath: dest.path).sorted()
            #expect(contents == ["a 2.txt", "a.txt"], "got \(contents)")
            #expect(read(dest.appending(path: "a.txt")) == "mine", "the file that was there changed")
        }

        /// Without smart extraction every item goes into the destination
        /// itself, so any of them can meet a name that is taken.
        @Test func smartOffKeepsWhatIsThere() async throws {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }

            let zip = try makeZip(in: dir, name: "scatter", entries: ["a.txt", "b.txt", "c.txt"])
            let dest = dir.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            try "mine".write(to: dest.appending(path: "a.txt"), atomically: true, encoding: .utf8)
            try "mine".write(to: dest.appending(path: "b.txt"), atomically: true, encoding: .utf8)

            try await extractFull(newState(), zip, to: dest, smart: false)

            let contents = try FileManager.default.contentsOfDirectory(atPath: dest.path).sorted()
            #expect(contents == ["a 2.txt", "a.txt", "b 2.txt", "b.txt", "c.txt"], "got \(contents)")
            #expect(read(dest.appending(path: "a.txt")) == "mine", "a.txt changed")
            #expect(read(dest.appending(path: "b.txt")) == "mine", "b.txt changed")
        }

        /// Extracting the same archive again gives it a folder of its own,
        /// numbered as Archive Utility numbers it rather than "scatter (2)".
        @Test func aSecondContainerIsNumberedLikeArchiveUtility() async throws {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }

            let zip = try makeZip(in: dir, name: "scatter", entries: ["a.txt", "b.txt"])
            let dest = dir.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

            try await extractFull(newState(), zip, to: dest)
            try await extractFull(newState(), zip, to: dest)

            let contents = try FileManager.default.contentsOfDirectory(atPath: dest.path).sorted()
            #expect(contents == ["scatter", "scatter 2"], "got \(contents)")
        }

        /// "Extract selected" moves what it extracted into the destination, and
        /// a name that was taken there made the move fail.
        @Test func extractSelectedIntoATakenNameGetsTheNextFreeOne() async throws {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }

            let zip = try makeZip(in: dir, name: "partial", entries: ["a.txt", "b.txt"])
            let dest = dir.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            try "mine".write(to: dest.appending(path: "a.txt"), atomically: true, encoding: .utf8)

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
            #expect(contents == ["a 2.txt", "a.txt"], "got \(contents)")
            #expect(read(dest.appending(path: "a.txt")) == "mine", "the file that was there changed")
        }

        /// The data loss: an entry that did not decode had what was written for
        /// it deleted, and with the password wrong that was the user's own file
        /// whenever the entry had its name. Cancelling the second prompt left
        /// the destination without it.
        @Test func aWrongPasswordLeavesTheFileOfTheSameNameAlone() async throws {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            try "mine".write(to: dir.appending(path: "hello world.txt"), atomically: true, encoding: .utf8)

            let state = newState()
            let answers = OneWrongAnswer()
            state.passwordProvider = { _ in await answers.next() }
            let zip = try #require(Bundle.module.url(forResource: "password", withExtension: nil))
                .appending(path: "zip_zipcrypto.zip")

            try await extractFull(state, zip, to: dir, smart: false)

            #expect(read(dir.appending(path: "hello world.txt")) == "mine", "the file that was there is gone or changed")
            let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
            #expect(contents == ["hello world.txt"], "the cancelled extraction left something behind: \(contents)")
        }

        // MARK: - Everything arrives

        /// Foundation's directory listings skip every name that starts with
        /// "._". The archive's listing takes `._notadouble.txt` for the sidecar
        /// of `notadouble.txt`, so smart extraction puts the archive flat into
        /// the destination too, and extraction writes it out as the plain file
        /// it is. Moving out what a listing of the staging folder returned
        /// left it behind, to be deleted with that folder.
        @Test(arguments: [true, false])
        func aFileNamedLikeASidecarArrivesToo(smart: Bool) async throws {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let zip = try #require(Bundle.module.url(forResource: "zip", withExtension: nil))
                .appending(path: "dotUnderscoreDecoy.zip")

            try await extractFull(newState(), zip, to: dir, smart: smart)

            #expect(read(dir.appending(path: "notadouble.txt")) == "The sibling that makes the decoy tempting.\n")
            #expect(read(dir.appending(path: "._notadouble.txt")) == "A real file that merely starts with dot-underscore.\n")
        }
    }
}
