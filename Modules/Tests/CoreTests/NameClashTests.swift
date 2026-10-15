//
//  NameClashTests.swift
//  Modules
//
//  An extracted item whose name is already taken where it goes: kept beside
//  what is there under a free name, or put in its place — the replaced file
//  deleted, or sent to the Trash and, where there is none, kept.
//

import Foundation
import Testing
@testable import Core

extension AllCoreTests {
    @MainActor struct NameClashTests {

        private func makeFolder() throws -> URL {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("NameClashTests_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        private func write(_ text: String, to url: URL) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }

        private func text(_ url: URL) throws -> String {
            String(decoding: try Data(contentsOf: url), as: UTF8.self)
        }

        private func names(in folder: URL) throws -> [String] {
            try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        }

        /// A file, and a folder holding one, extracted to `work`, ready to be
        /// placed: `a.txt` and `docs/b.txt`, each saying "new".
        private func extracted(in dir: URL) throws -> [(source: URL, name: String)] {
            let work = dir.appendingPathComponent("work")
            try write("new", to: work.appendingPathComponent("a.txt"))
            try write("new", to: work.appendingPathComponent("docs/b.txt"))
            return [(work.appendingPathComponent("a.txt"), "a.txt"), (work.appendingPathComponent("docs"), "docs")]
        }

        /// A destination already holding `a.txt` and `docs/b.txt`, each "mine".
        private func destination(in dir: URL) throws -> URL {
            let dest = dir.appendingPathComponent("dest")
            try write("mine", to: dest.appendingPathComponent("a.txt"))
            try write("mine", to: dest.appendingPathComponent("docs/b.txt"))
            return dest
        }

        // MARK: - Free names

        @Test func aFreeNameIsNumberedBeforeAFilesExtension() throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            try write("x", to: dir.appendingPathComponent("photo.jpg"))
            try write("x", to: dir.appendingPathComponent("photo (2).jpg"))
            try FileManager.default.createDirectory(at: dir.appendingPathComponent("v1.2"), withIntermediateDirectories: true)

            #expect(NameClash.freeName(for: "photo.jpg", in: dir, isFolder: false) == "photo (3).jpg")
            #expect(NameClash.freeName(for: "v1.2", in: dir) == "v1.2 (2)")
            #expect(NameClash.freeName(for: "free.txt", in: dir, isFolder: false) == "free.txt")
            // and what this placement has taken itself
            #expect(NameClash.freeName(for: "free.txt", in: dir, isFolder: false, reserved: ["free.txt"]) == "free (2).txt")
        }

        @Test func aBrokenLinkTakesItsName() throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            try FileManager.default.createSymbolicLink(
                atPath: dir.appendingPathComponent("gone").path, withDestinationPath: "/nowhere/at/all")
            #expect(NameClash.freeName(for: "gone", in: dir) == "gone (2)")
        }

        @Test func unsetIsKeepBoth() {
            let defaults = isolatedDefaults()
            #expect(NameClash.current(in: defaults) == .keepBoth)
            defaults.set(NameClash.replace.rawValue, forKey: Keys.nameClash)
            #expect(NameClash.current(in: defaults) == .replace)
        }

        // MARK: - Placing

        @Test func keepBothLeavesWhatIsThereAlone() throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            let dest = try destination(in: dir)

            try ExtractionStaging.place(try extracted(in: dir), into: dest, clash: .keepBoth)

            #expect(try names(in: dest) == ["a (2).txt", "a.txt", "docs", "docs (2)"])
            #expect(try text(dest.appendingPathComponent("a.txt")) == "mine")
            #expect(try text(dest.appendingPathComponent("docs/b.txt")) == "mine")
            #expect(try text(dest.appendingPathComponent("a (2).txt")) == "new")
            #expect(try text(dest.appendingPathComponent("docs (2)/b.txt")) == "new")
        }

        @Test func replaceDeletesWhatItReplaces() throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            let dest = try destination(in: dir)
            var trashed: [URL] = []

            try ExtractionStaging.place(try extracted(in: dir), into: dest, clash: .replace, trash: { trashed.append($0) })

            #expect(try names(in: dest) == ["a.txt", "docs"])
            #expect(try text(dest.appendingPathComponent("a.txt")) == "new")
            #expect(try text(dest.appendingPathComponent("docs/b.txt")) == "new")
            #expect(trashed.isEmpty)
        }

        /// The replaced files go to the Trash under their own names; the
        /// folder they were in is extracted into, as with Replace.
        @Test func replaceToTrashSendsTheReplacedFilesToTheTrash() throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            let dest = try destination(in: dir)
            let bin = dir.appendingPathComponent("bin")
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            var count = 0
            let trash: (URL) throws -> Void = { file in
                count += 1
                try FileManager.default.moveItem(at: file, to: bin.appendingPathComponent("\(count)-\(file.lastPathComponent)"))
            }

            try ExtractionStaging.place(try extracted(in: dir), into: dest, clash: .replaceToTrash, trash: trash)

            #expect(try names(in: dest) == ["a.txt", "docs"])
            #expect(try text(dest.appendingPathComponent("a.txt")) == "new")
            #expect(try text(dest.appendingPathComponent("docs/b.txt")) == "new")
            #expect(try names(in: bin) == ["1-a.txt", "2-b.txt"])
            #expect(try text(bin.appendingPathComponent("1-a.txt")) == "mine")
            #expect(try text(bin.appendingPathComponent("2-b.txt")) == "mine")
        }

        /// No Trash to go to — a network volume — and the replaced file stays,
        /// under a free name beside its replacement.
        @Test func aReplacedFileWithNoTrashToGoToIsKept() throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            let dest = try destination(in: dir)

            try ExtractionStaging.place(
                try extracted(in: dir), into: dest, clash: .replaceToTrash,
                trash: { _ in throw CocoaError(.featureUnsupported) })

            #expect(try names(in: dest) == ["a (2).txt", "a.txt", "docs"])
            #expect(try text(dest.appendingPathComponent("a.txt")) == "new")
            #expect(try text(dest.appendingPathComponent("a (2).txt")) == "mine")
            #expect(try names(in: dest.appendingPathComponent("docs")) == ["b (2).txt", "b.txt"])
        }

        // MARK: - Through an extraction

        /// Builds `<name>.zip` in `dir` from the given entries with the system
        /// `zip`; each file holds "new".
        private func makeZip(in dir: URL, name: String, entries: [String]) throws -> URL {
            let src = dir.appendingPathComponent("src-\(name)")
            for entry in entries {
                if entry.hasSuffix("/") {
                    try FileManager.default.createDirectory(at: src.appendingPathComponent(entry), withIntermediateDirectories: true)
                } else {
                    try write("new", to: src.appendingPathComponent(entry))
                }
            }
            let zip = dir.appendingPathComponent("\(name).zip")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            p.arguments = ["-r", zip.path] + entries
            p.currentDirectoryURL = src
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run()
            p.waitUntilExit()
            #expect(p.terminationStatus == 0)
            return zip
        }

        /// Runs `extraction` on `state` to its end.
        private func run(_ state: ArchiveState, _ extraction: () -> Void) async {
            await withCheckedContinuation { continuation in
                state.onStatusChange = { status in
                    if status == .done { continuation.resume() }
                }
                extraction()
            }
        }

        private func opened(_ zip: URL, clash: NameClash) async throws -> ArchiveState {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.progressCenter = ExtractionProgressCenter()
            state.nameClash = { clash }
            state.open(url: zip)
            try await state.openTask?.value
            return state
        }

        /// One top-level folder goes straight into the destination, where one
        /// of that name already is.
        @Test func extractArchiveKeepsBoth() async throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            let zip = try makeZip(in: dir, name: "trip", entries: ["photos/c.jpg"])
            let dest = dir.appendingPathComponent("out")
            try write("mine", to: dest.appendingPathComponent("photos/c.jpg"))

            let state = try await opened(zip, clash: .keepBoth)
            await run(state) { state.extract(to: dest, smart: true) }

            #expect(try names(in: dest) == ["photos", "photos (2)"])
            #expect(try text(dest.appendingPathComponent("photos/c.jpg")) == "mine")
            #expect(try text(dest.appendingPathComponent("photos (2)/c.jpg")) == "new")
        }

        /// "Extract selected" onto a name that is taken used to fail; it now
        /// does as the setting says.
        @Test(arguments: [NameClash.keepBoth, .replace])
        func extractSelectedOntoATakenName(clash: NameClash) async throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            let zip = try makeZip(in: dir, name: "trip", entries: ["a.txt", "b.txt"])
            let dest = dir.appendingPathComponent("out")
            try write("mine", to: dest.appendingPathComponent("a.txt"))

            let state = try await opened(zip, clash: clash)
            let item = try #require(state.entries.values.first { $0.name == "a.txt" })
            await run(state) { state.extract(items: [item], to: dest, smart: false) }
            #expect(state.error == nil)

            switch clash {
            case .keepBoth:
                #expect(try names(in: dest) == ["a (2).txt", "a.txt"])
                #expect(try text(dest.appendingPathComponent("a.txt")) == "mine")
                #expect(try text(dest.appendingPathComponent("a (2).txt")) == "new")
            default:
                #expect(try names(in: dest) == ["a.txt"])
                #expect(try text(dest.appendingPathComponent("a.txt")) == "new")
            }
        }
    }
}
