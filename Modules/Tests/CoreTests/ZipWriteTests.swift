//
//  ZipWriteTests.swift
//  Modules
//
//  Created by Stephan Arenswald on 16.07.26.
//
//  Zip create/delete tests. All fixtures are generated at test time —
//  none of the checked-in test archives are used (or modified).
//

import Testing
import Foundation
import Swift7zip
@testable import Core

// MARK: - Fixture helpers

/// Creates a fresh temp directory for one test.
private func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ZipWriteTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Runs a CLI tool and returns stdout. Used to build/verify fixtures with
/// the system zip tools so our writer is verified independently.
@discardableResult
private func run(_ tool: String, _ args: [String], cwd: URL? = nil) throws -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    if let cwd { p.currentDirectoryURL = cwd }
    let out = Pipe()
    p.standardOutput = out
    p.standardError = out
    try p.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    let text = String(data: data, encoding: .utf8) ?? ""
    #expect(p.terminationStatus == 0, "\(tool) \(args.joined(separator: " ")) failed: \(text)")
    return text
}

/// Builds a zip fixture with the system `zip` CLI (independent of our writer):
/// root.txt, folder/one.txt, folder/two.txt, other/keep.txt
private func makeSystemZipFixture(in dir: URL) throws -> URL {
    let src = dir.appendingPathComponent("src")
    try FileManager.default.createDirectory(at: src.appendingPathComponent("folder"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: src.appendingPathComponent("other"), withIntermediateDirectories: true)
    try "root".write(to: src.appendingPathComponent("root.txt"), atomically: true, encoding: .utf8)
    try "one".write(to: src.appendingPathComponent("folder/one.txt"), atomically: true, encoding: .utf8)
    try "two".write(to: src.appendingPathComponent("folder/two.txt"), atomically: true, encoding: .utf8)
    try "keep".write(to: src.appendingPathComponent("other/keep.txt"), atomically: true, encoding: .utf8)
    let zip = dir.appendingPathComponent("fixture.zip")
    try run("/usr/bin/zip", ["-r", zip.path, "root.txt", "folder", "other"], cwd: src)
    return zip
}

/// Entry paths as listed by the independent system tool (`unzip -Z1`).
private func systemZipList(_ zip: URL) throws -> Set<String> {
    let out = try run("/usr/bin/unzip", ["-Z1", zip.path])
    return Set(out.split(separator: "\n").map(String.init))
}

// MARK: - Writer-level tests (SevenZipArchive.writeArchive)

extension AllCoreTests {
    struct ZipWriteTests {

        @Test func createNewZipWithFilesAndFolder() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }

            // input files on disk
            let fileA = dir.appendingPathComponent("a.txt")
            try "hello a".write(to: fileA, atomically: true, encoding: .utf8)

            let dest = dir.appendingPathComponent("new.zip")
            try SevenZipArchive.writeArchive(
                destination: dest,
                items: [
                    .addFile(archivePath: "a.txt", diskPath: fileA),
                    .addDirectory(archivePath: "sub"),
                    .addData(archivePath: "sub/b.txt", data: Data("hello b".utf8)),
                ],
                options: .init(format: .zip)
            )

            // verify with the independent system tool
            let listed = try systemZipList(dest)
            #expect(listed.contains("a.txt"))
            #expect(listed.contains("sub/b.txt"))
            // integrity check
            try run("/usr/bin/unzip", ["-t", dest.path])

            // verify contents by extracting with the system tool
            let out = dir.appendingPathComponent("out")
            try run("/usr/bin/unzip", [dest.path, "-d", out.path])
            #expect(try String(contentsOf: out.appendingPathComponent("a.txt"), encoding: .utf8) == "hello a")
            #expect(try String(contentsOf: out.appendingPathComponent("sub/b.txt"), encoding: .utf8) == "hello b")
        }

        @Test func deleteFileFromZip() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let zip = try makeSystemZipFixture(in: dir)

            // find the source index of folder/one.txt with our reader
            let archive = try SevenZipArchive(url: zip)
            let victim = try #require(try archive.entries.first { $0.path == "folder/one.txt" })

            try SevenZipArchive.writeArchive(
                source: zip,
                destination: zip,
                items: [.remove(sourceIndex: victim.index)]
            )

            let listed = try systemZipList(zip)
            #expect(!listed.contains("folder/one.txt"))
            #expect(listed.contains("folder/two.txt"))
            #expect(listed.contains("root.txt"))
            #expect(listed.contains("other/keep.txt"))
            try run("/usr/bin/unzip", ["-t", zip.path])

            // remaining file still extracts with its original content
            let out = dir.appendingPathComponent("out")
            try run("/usr/bin/unzip", [zip.path, "-d", out.path])
            #expect(try String(contentsOf: out.appendingPathComponent("folder/two.txt"), encoding: .utf8) == "two")
        }

        @Test func deleteFolderFromZip() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let zip = try makeSystemZipFixture(in: dir)

            // remove the folder entry and everything below it
            let archive = try SevenZipArchive(url: zip)
            let doomed = try archive.entries.filter {
                $0.path == "folder" || $0.path.hasPrefix("folder/")
            }
            #expect(doomed.count == 3) // folder/, one.txt, two.txt

            try SevenZipArchive.writeArchive(
                source: zip,
                destination: zip,
                items: doomed.map { .remove(sourceIndex: $0.index) }
            )

            let listed = try systemZipList(zip)
            #expect(!listed.contains { $0.hasPrefix("folder") })
            #expect(listed.contains("root.txt"))
            #expect(listed.contains("other/keep.txt"))
            try run("/usr/bin/unzip", ["-t", zip.path])
        }

        /// A moved (renamed) entry keeps its original POSIX mode: the writer
        /// recovers it from the source archive rather than storing mode 000.
        @Test func moveKeepsPosixMode() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }

            // a file with a distinctive, non-default mode
            let src = dir.appendingPathComponent("src")
            try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
            let file = src.appendingPathComponent("orig.txt")
            try "hi".write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o750], ofItemAtPath: file.path)

            let zip = dir.appendingPathComponent("fixture.zip")
            try run("/usr/bin/zip", [zip.path, "orig.txt"], cwd: src)

            // sanity: the source entry carries 0o750
            let source = try SevenZipArchive(url: zip)
            let orig = try #require(try source.entries.first { $0.path == "orig.txt" })
            #expect(orig.posixPermissions == 0o750)

            // rename it into a new archive
            let dest = dir.appendingPathComponent("out.zip")
            try SevenZipArchive.writeArchive(
                source: zip,
                destination: dest,
                items: [.move(sourceIndex: orig.index, newPath: "renamed.txt")]
            )

            // the renamed entry must still carry 0o750, not 000
            let result = try SevenZipArchive(url: dest)
            let moved = try #require(try result.entries.first { $0.path == "renamed.txt" })
            #expect(moved.posixPermissions == 0o750)
        }

        /// Save As on a clean (unedited) archive writes a full copy to the new
        /// destination, even with no pending changes.
        @MainActor @Test func saveAsCopiesCleanArchive() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let zip = try makeSystemZipFixture(in: dir)

            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.open(url: zip)
            try await state.openTask?.value
            #expect(!state.hasPendingChanges)   // nothing edited

            let dest = dir.appendingPathComponent("copy.zip")
            await state.save(to: dest)?.value

            // the copy exists and carries the same entries as the source
            let listed = try systemZipList(dest)
            #expect(listed.contains("root.txt"))
            #expect(listed.contains("folder/one.txt"))
            #expect(listed.contains("other/keep.txt"))
        }

        @Test func reportsProgressWhileWriting() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }

            // a few MB of incompressible data so the writer actually spends
            // time and 7-Zip emits progress checkpoints
            var big = Data(count: 4 * 1024 * 1024)
            for i in stride(from: 0, to: big.count, by: 977) { big[i] = UInt8(i & 0xFF) }
            let payload = dir.appendingPathComponent("big.bin")
            try big.write(to: payload)

            final class Sink: @unchecked Sendable {
                var samples: [(UInt64, UInt64)] = []
            }
            let sink = Sink()

            let dest = dir.appendingPathComponent("prog.zip")
            try SevenZipArchive.writeArchive(
                destination: dest,
                items: [.addFile(archivePath: "big.bin", diskPath: payload)],
                options: .init(format: .zip, level: 1),
                progress: { completed, total in
                    sink.samples.append((completed, total))
                    return true
                }
            )

            // callback fired, total was known, and completion reached it
            #expect(!sink.samples.isEmpty, "no progress callbacks")
            let total = sink.samples.map(\.1).max() ?? 0
            #expect(total > 0, "total bytes never reported")
            let maxCompleted = sink.samples.map(\.0).max() ?? 0
            #expect(maxCompleted == total, "did not reach 100% (\(maxCompleted)/\(total))")
            try run("/usr/bin/unzip", ["-t", dest.path])
        }

        @Test func addFileToExistingZip() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let zip = try makeSystemZipFixture(in: dir)

            try SevenZipArchive.writeArchive(
                source: zip,
                destination: zip,
                items: [.addData(archivePath: "added.txt", data: Data("added".utf8))]
            )

            let listed = try systemZipList(zip)
            #expect(listed.contains("added.txt"))
            #expect(listed.contains("root.txt"))
            try run("/usr/bin/unzip", ["-t", zip.path])
        }
    }

    // MARK: - State-level tests (create / delete via ArchiveState)

    @MainActor struct ZipStateEditTests {

        private func makeState() -> ArchiveState {
            ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
        }

        /// Finds the loaded entry with the given in-archive path.
        private func item(_ path: String, in state: ArchiveState) -> ArchiveItem? {
            state.entries.values.first { $0.virtualPath == path }
        }

        @Test func createNewArchiveViaState() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }

            // files on disk to pack: a.txt + folder with a nested file
            let fileA = dir.appendingPathComponent("a.txt")
            try "hello a".write(to: fileA, atomically: true, encoding: .utf8)
            let folder = dir.appendingPathComponent("stuff")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try "nested".write(to: folder.appendingPathComponent("inner.txt"), atomically: true, encoding: .utf8)

            let state = makeState()
            state.create()
            #expect(state.canBeEdited)
            state.add(url: fileA)
            state.add(url: folder)
            #expect(state.hasPendingChanges)

            let dest = dir.appendingPathComponent("created.zip")
            let saveTask = try #require(state.save(to: dest))
            await saveTask.value

            // the file exists, is a valid zip, and holds all added items
            let listed = try systemZipList(dest)
            #expect(listed.contains("a.txt"))
            #expect(listed.contains("stuff/inner.txt"))
            try run("/usr/bin/unzip", ["-t", dest.path])

            // the state reloaded the archive from disk
            #expect(state.url == dest)
            #expect(!state.hasPendingChanges)
            #expect(state.entries.values.contains { $0.name == "a.txt" })
        }

        @Test func deleteFileViaState() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let zip = try makeSystemZipFixture(in: dir)

            let state = makeState()
            state.open(url: zip)
            try await state.openTask?.value
            #expect(state.canBeEdited)

            let victim = try #require(item("folder/one.txt", in: state))
            state.remove(items: [victim])
            #expect(state.hasPendingChanges)

            let saveTask = try #require(state.save())
            await saveTask.value

            // gone from the file (independent verification) and from the state
            let listed = try systemZipList(zip)
            #expect(!listed.contains("folder/one.txt"))
            #expect(listed.contains("folder/two.txt"))
            try run("/usr/bin/unzip", ["-t", zip.path])
            #expect(item("folder/one.txt", in: state) == nil)
            #expect(item("folder/two.txt", in: state) != nil)

            // The reopen after saving must not leave the previous load's
            // entries behind: the reloaded count matches a fresh open.
            let fresh = makeState()
            fresh.open(url: zip)
            try await fresh.openTask?.value
            #expect(state.itemCount == fresh.itemCount,
                    "stale entries after save-reload: \(state.itemCount) vs \(fresh.itemCount)")
        }

        @Test func deleteFolderViaState() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let zip = try makeSystemZipFixture(in: dir)

            let state = makeState()
            state.open(url: zip)
            try await state.openTask?.value

            let folder = try #require(item("folder", in: state))
            state.remove(items: [folder])
            let saveTask = try #require(state.save())
            await saveTask.value

            let listed = try systemZipList(zip)
            #expect(!listed.contains { $0.hasPrefix("folder") })
            #expect(listed.contains("root.txt"))
            #expect(listed.contains("other/keep.txt"))
            try run("/usr/bin/unzip", ["-t", zip.path])
        }

        @Test func mutationsRefusedWhileSaving() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let fileA = dir.appendingPathComponent("a.txt")
            try "a".write(to: fileA, atomically: true, encoding: .utf8)
            let extra = dir.appendingPathComponent("extra.txt")
            try "extra".write(to: extra, atomically: true, encoding: .utf8)

            let state = makeState()
            state.create()
            state.add(url: fileA)
            let pendingBefore = state.diff.count

            // save() flips isSaving synchronously before handing back its Task,
            // so the window between here and awaiting is a real "saving" state.
            let dest = dir.appendingPathComponent("out.zip")
            let saveTask = try #require(state.save(to: dest))
            #expect(state.isSaving)

            // every mutating entry point must refuse while a save is running
            state.add(url: extra)
            #expect(state.diff.count == pendingBefore, "add slipped in during save")

            if let victim = state.entries.values.first(where: { $0.name == "a.txt" }) {
                state.remove(items: [victim])
            }
            #expect(state.diff.count == pendingBefore, "delete slipped in during save")

            #expect(state.save(to: dest) == nil, "re-entrant save was allowed")

            await saveTask.value
            #expect(!state.isSaving)

            // the archive holds exactly what was pending when the save started
            let listed = try systemZipList(dest)
            #expect(listed == ["a.txt"], "unexpected contents: \(listed)")
        }

        @Test func removePendingAdditionBeforeSave() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let zip = try makeSystemZipFixture(in: dir)
            let extra = dir.appendingPathComponent("extra.txt")
            try "extra".write(to: extra, atomically: true, encoding: .utf8)

            let state = makeState()
            state.open(url: zip)
            try await state.openTask?.value

            // add a file, then remove it again before saving — no net change
            state.add(url: extra)
            let pending = try #require(item("extra.txt", in: state))
            state.remove(items: [pending])
            #expect(!state.hasPendingChanges)
        }
    }
}
