//
//  FolderAddTests.swift
//  Modules
//
//  Adding folders from disk: read off the main actor, put into the archive in
//  one go, and — for a compress with no window of its own — reported to the
//  progress center. All of it from #278, a project of 20,000 files that took
//  11 seconds to start compressing, with the app frozen and nothing to show.
//

import Combine
import Testing
import Foundation
@testable import Swift7zip
@testable import Core

/// A project folder: `files` small files, eight to a folder, the folders nested
/// the way a build leaves them.
func makeProject(named name: String = "FileApex", in dir: URL, files: Int) throws -> URL {
    let project = dir.appendingPathComponent(name)
    for index in 0..<files {
        let folder = project.appendingPathComponent("module\(index / 64)/build/out\(index / 8)")
        if index % 8 == 0 {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try Data("class Class\(index)".utf8).write(to: folder.appendingPathComponent("Class\(index).kt"))
    }
    return project
}

/// The archive path of every pending addition, in the order a save writes them.
@MainActor private func pendingPaths(_ state: ArchiveState) -> [String] {
    state.diff.compactMap { item in
        switch item {
        case .addFile(let path, _, _, _), .addDirectory(let path, _, _, _), .addData(let path, _, _, _): path
        default: nil
        }
    }
}

extension AllCoreTests {

    @MainActor struct FolderAddTests {

        private func makeState() -> ArchiveState {
            ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
        }

        /// The turns something else gets on the main actor.
        @MainActor private final class Turns {
            var count = 0
        }

        /// The main actor keeps running other work while a folder is read. It
        /// used to be read on it, file by file, with nothing else getting a
        /// turn until the last one: no drawing, no progress, no cancel.
        @Test func addingAFolderLeavesTheMainActorFree() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let project = try makeProject(in: dir, files: 2_000)
            let state = makeState()
            state.create()

            // Something else that wants the main actor, the way the UI does.
            let turns = Turns()
            let other = Task {
                while !Task.isCancelled {
                    turns.count += 1
                    await Task.yield()
                }
            }
            defer { other.cancel() }

            let adding = state.add(url: project)
            let before = turns.count
            #expect(await adding.value)
            let during = turns.count - before

            #expect(pendingPaths(state).contains("FileApex/module0/build/out0/Class0.kt"))
            // Read on the main actor, the add leaves it a turn before it starts
            // and one after it ends, and none in between.
            #expect(during > 100, "the main actor got \(during) turns while the folder was read")
        }

        /// What was read goes into the archive in one go. `diff` and `entries`
        /// are published, and changed entry by entry each change copied all of
        /// them: for 20,000 files most of the 11 seconds.
        @Test func addingAFolderChangesTheArchiveOnce() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let project = try makeProject(in: dir, files: 400)
            let onDisk = (FileManager.default.subpaths(atPath: project.path) ?? []).count + 1
            let state = makeState()
            state.create()

            var diffChanges = 0
            var entriesChanges = 0
            let watching = [
                state.$diff.dropFirst().sink { _ in diffChanges += 1 },
                state.$entries.dropFirst().sink { _ in entriesChanges += 1 },
            ]
            defer { watching.forEach { $0.cancel() } }

            #expect(await state.add(url: project).value)

            #expect(state.diff.count == onDisk)
            #expect(state.itemCount == onDisk)
            #expect(diffChanges == 1, "diff changed \(diffChanges) times")
            #expect(entriesChanges == 1, "entries changed \(entriesChanges) times")
        }

        /// However many files come in one add, the archive changes once. A drop
        /// onto a window hands everything it holds to one add for that reason:
        /// added file by file, a thousand files were a thousand reads, a
        /// thousand changes and a thousand reloads of the list.
        @Test func manyFilesInOneAddChangeTheArchiveOnce() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let files = try (0..<300).map { index -> URL in
                let file = dir.appendingPathComponent("file\(index).txt")
                try Data("file \(index)".utf8).write(to: file)
                return file
            }
            let state = makeState()
            state.create()

            var diffChanges = 0
            var entriesChanges = 0
            let watching = [
                state.$diff.dropFirst().sink { _ in diffChanges += 1 },
                state.$entries.dropFirst().sink { _ in entriesChanges += 1 },
            ]
            defer { watching.forEach { $0.cancel() } }

            #expect(await state.add(urls: files).value)

            // in the order they were handed over
            #expect(pendingPaths(state) == files.map(\.lastPathComponent))
            #expect(diffChanges == 1, "diff changed \(diffChanges) times")
            #expect(entriesChanges == 1, "entries changed \(entriesChanges) times")
        }

        /// A plain walk of `folder`: every folder listed, every entry looked at
        /// once. The least that reading it can take, on this machine, right now.
        private func walk(_ folder: URL) throws -> Int {
            var seen = 0
            for entry in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                var status = stat()
                #expect(lstat(entry.path, &status) == 0)
                seen += 1
                if status.st_mode & S_IFMT == S_IFDIR {
                    seen += try walk(entry)
                }
            }
            return seen
        }

        /// A limit on time, where the tests above watch for the two causes that
        /// were found: adding 20,000 files costs no more than a few times a
        /// plain walk of them. Measured against the walk, not in seconds: the
        /// same add takes 0.3 seconds on the machine this was written on and
        /// 1.4 on the CI runner, whose disk is that much slower, so a number of
        /// seconds is either too tight there or too loose here. The walk on the
        /// main actor took 13 seconds here, a hundred times its own walk.
        ///
        /// Up to three tries, and one good one is enough: a busy machine only
        /// ever makes a run slower.
        @Test func addingTwentyThousandFilesCostsLittleMoreThanWalkingThem() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let project = try makeProject(in: dir, files: 20_000)
            let allowed = 6.0

            var tries: [(add: Duration, walk: Duration)] = []
            for _ in 0..<3 where !tries.contains(where: { $0.add < $0.walk * allowed }) {
                var start = ContinuousClock.now
                let onDisk = try walk(project) + 1
                let walking = ContinuousClock.now - start

                let state = makeState()
                state.create()
                start = ContinuousClock.now
                #expect(await state.add(url: project).value)
                tries.append((ContinuousClock.now - start, walking))
                #expect(state.diff.count == onDisk)
            }

            // in the log of every run, so the headroom on a given machine shows
            print("Adding 20,000 files, and a plain walk of them: \(tries)")
            #expect(tries.contains { $0.add < $0.walk * allowed },
                    "adding 20,000 files took more than \(allowed) times a walk of them: \(tries)")
        }

        /// Taking a folder out again is one change as well: it used to drop its
        /// entries one by one, the same copy for each.
        @Test func removingAFolderChangesTheArchiveOnce() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let project = try makeProject(in: dir, files: 400)
            let state = makeState()
            state.create()
            #expect(await state.add(url: project).value)
            let folder = try #require(state.childItems?.first)

            var diffChanges = 0
            var entriesChanges = 0
            let watching = [
                state.$diff.dropFirst().sink { _ in diffChanges += 1 },
                state.$entries.dropFirst().sink { _ in entriesChanges += 1 },
            ]
            defer { watching.forEach { $0.cancel() } }

            state.remove(items: [folder])

            #expect(state.diff.isEmpty, "\(state.diff.count) additions are still pending")
            #expect(state.itemCount == 0)
            #expect(diffChanges == 1, "diff changed \(diffChanges) times")
            #expect(entriesChanges == 1, "entries changed \(entriesChanges) times")
        }

        /// What the window shows for a pending entry is what the disk says about
        /// it, and the entries come in the order they always did: a folder, then
        /// what it holds, by name. A link is an entry of its own, not followed.
        @Test func whatIsAddedShowsAsItIsOnDisk() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let fm = FileManager.default
            let project = dir.appendingPathComponent("Project")
            let build = project.appendingPathComponent("build")
            try fm.createDirectory(at: build, withIntermediateDirectories: true)
            try "fun main() {}".write(to: project.appendingPathComponent("Main.kt"), atomically: true, encoding: .utf8)
            try "SECRET=1".write(to: project.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
            try "#!/bin/sh".write(to: project.appendingPathComponent("run.sh"), atomically: true, encoding: .utf8)
            try Data(count: 4_096).write(to: build.appendingPathComponent("app.jar"))
            try fm.createSymbolicLink(at: project.appendingPathComponent("link"), withDestinationURL: build)
            try fm.setAttributes([.posixPermissions: 0o640], ofItemAtPath: project.appendingPathComponent("Main.kt").path)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: project.appendingPathComponent("run.sh").path)
            try fm.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)],
                ofItemAtPath: build.appendingPathComponent("app.jar").path)

            let state = makeState()
            state.create()
            #expect(await state.add(url: project).value)

            #expect(pendingPaths(state) == [
                "Project", "Project/.env", "Project/Main.kt", "Project/build", "Project/build/app.jar",
                "Project/link", "Project/run.sh",
            ])
            for path in pendingPaths(state) {
                let item = try #require(state.entries.values.first { $0.virtualPath == path }, "\(path) is not shown")
                let onDisk = dir.appendingPathComponent(path)
                let attributes = try fm.attributesOfItem(atPath: onDisk.path)
                let isFolder = attributes[.type] as? FileAttributeType == .typeDirectory
                #expect(item.type == (isFolder ? .directory : .file), "\(path)")
                #expect(item.uncompressedSize == (attributes[.size] as? NSNumber)?.intValue, "\(path)")
                #expect(item.modificationDate == attributes[.modificationDate] as? Date, "\(path)")
                #expect(item.posixPermissions == (attributes[.posixPermissions] as? NSNumber)?.intValue, "\(path)")
                #expect(item.name == onDisk.lastPathComponent)
            }
            let link = try #require(state.entries.values.first { $0.virtualPath == "Project/link" })
            #expect(link.children == nil, "the link was followed")
            // and the tree is the one on disk
            let shown = try #require(state.entries.values.first { $0.virtualPath == "Project" })
            let names = (shown.children ?? []).compactMap { state.entries[$0]?.name }
            #expect(names == [".env", "Main.kt", "build", "link", "run.sh"])
        }

        /// Adds take their turn: a folder still being read does not get passed
        /// by a single file dropped after it.
        @Test func addsLandInTheOrderTheyWereStarted() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let project = try makeProject(in: dir, files: 400)
            let single = dir.appendingPathComponent("notes.txt")
            try "notes".write(to: single, atomically: true, encoding: .utf8)
            let state = makeState()
            state.create()

            state.add(url: project)
            #expect(await state.add(url: single).value)

            #expect(pendingPaths(state).first == "FileApex")
            #expect(pendingPaths(state).last == "notes.txt")
        }

        /// Two things of one name can come in one add — picked from different
        /// folders. They meet as they would have one after the other: the later
        /// file replaces what was there, a folder is merged into a folder.
        @Test func aNameTwiceInOneAddIsInTheArchiveOnce() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let fm = FileManager.default
            for (place, file) in [("first", "a.txt"), ("second", "b.txt")] {
                let src = dir.appendingPathComponent("\(place)/src")
                try fm.createDirectory(at: src, withIntermediateDirectories: true)
                try place.write(to: src.appendingPathComponent(file), atomically: true, encoding: .utf8)
                try place.write(to: dir.appendingPathComponent("\(place)/notes.txt"), atomically: true, encoding: .utf8)
            }
            // a folder in one place, a file of the same name in the other
            try fm.createDirectory(at: dir.appendingPathComponent("first/build"), withIntermediateDirectories: true)
            try "jar".write(to: dir.appendingPathComponent("first/build/app.jar"), atomically: true, encoding: .utf8)
            try "not a folder".write(to: dir.appendingPathComponent("second/build"), atomically: true, encoding: .utf8)
            let picked = ["first/notes.txt", "second/notes.txt", "first/src", "second/src", "first/build", "second/build"]
                .map { dir.appendingPathComponent($0) }

            let state = makeState()
            state.create()
            #expect(await state.add(urls: picked).value)

            #expect(pendingPaths(state) == ["notes.txt", "src", "src/a.txt", "src/b.txt", "build"])
            #expect(state.itemCount == 5)
            let dest = dir.appendingPathComponent("out.zip")
            await state.save(to: dest)?.value
            #expect(state.error == nil, "\(state.error ?? "")")
            #expect(try systemZipEntries(dest).sorted() == ["build", "notes.txt", "src/", "src/a.txt", "src/b.txt"])
            let extracted = dir.appendingPathComponent("extracted")
            try run("/usr/bin/unzip", ["-q", dest.path, "-d", extracted.path])
            #expect(try String(contentsOf: extracted.appendingPathComponent("notes.txt"), encoding: .utf8) == "second")
            #expect(try String(contentsOf: extracted.appendingPathComponent("build"), encoding: .utf8) == "not a folder")
        }

        /// The status bar's cancel stops what is being read, and what was waiting
        /// behind it, and leaves the archive as it was. For a load the same
        /// button ends in an empty window; an add is not a load.
        @Test func cancellingAnAddLeavesTheArchiveAsItWas() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let project = try makeProject(in: dir, files: 2_000)
            let first = dir.appendingPathComponent("first.txt")
            let later = dir.appendingPathComponent("later.txt")
            try "first".write(to: first, atomically: true, encoding: .utf8)
            try "later".write(to: later, atomically: true, encoding: .utf8)
            let state = makeState()
            state.create()
            #expect(await state.add(url: first).value)

            let adding = state.add(url: project)
            let waiting = state.add(url: later)
            // busy from the moment the folder is being read
            for _ in 0..<1_000 where !state.isBusy { await Task.yield() }
            #expect(state.isBusy)
            state.cancelCurrentOperation()

            #expect(await !adding.value)
            #expect(await !waiting.value)
            #expect(state.hasArchive, "the cancel closed the archive")
            #expect(pendingPaths(state) == ["first.txt"])
            #expect(!state.isBusy)
            // and it takes files again
            #expect(await state.add(url: later).value)
            #expect(pendingPaths(state) == ["first.txt", "later.txt"])
        }

        /// What an add was reading for is gone by the time it is read: the
        /// window shows another archive now, and that one does not get it.
        @Test func anAddIsDroppedOnceItsArchiveIsGone() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let project = try makeProject(in: dir, files: 64)
            let state = makeState()
            state.create()

            let adding = state.add(url: project)
            state.create(named: "Another")

            #expect(await !adding.value)
            #expect(state.diff.isEmpty, "\(state.diff.count) entries went into the wrong archive")
            #expect(state.itemCount == 0)
        }

        /// A save does not go ahead of files still being read: it would write the
        /// archive without them.
        @Test func nothingIsSavedWhileFilesAreStillBeingAdded() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let project = try makeProject(in: dir, files: 64)
            let dest = dir.appendingPathComponent("out.zip")
            let state = makeState()
            state.create()

            let adding = state.add(url: project)
            #expect(state.save(to: dest) == nil, "saved before the folder was read")
            #expect(await adding.value)
            #expect(!FileManager.default.fileExists(atPath: dest.path))

            await state.save(to: dest)?.value
            #expect(state.error == nil, "\(state.error ?? "")")
            #expect(try systemZipList(dest).contains("FileApex/module0/build/out0/Class0.kt"))
        }
    }

    // MARK: - Metadata sidecars

    struct SidecarSelectionTests {

        /// A sidecar is packed only for what has something to carry. Packing one
        /// to find out it says nothing cost two scratch files and a read per
        /// entry: 8 seconds for 20,000 ordinary files, before anything was
        /// written. What goes into the archive is unchanged — the tests around
        /// `createdArchiveKeepsExtendedAttributes` say what that is.
        @Test func onlyWhatHasMetadataIsPackedForASidecar() throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let fm = FileManager.default
            func file(_ name: String) throws -> URL {
                let url = dir.appendingPathComponent(name)
                try "contents".write(to: url, atomically: true, encoding: .utf8)
                return url
            }
            func tag(_ url: URL, _ name: String) {
                let value = Array("value".utf8)
                #expect(setxattr(url.path, name, value, value.count, 0, 0) == 0, "could not set \(name)")
            }

            let plain = try file("plain.txt")
            #expect(try !SevenZipArchive.carriesMetadata(plain))

            let commented = try file("commented.txt")
            tag(commented, "com.apple.metadata:kMDItemComment")
            #expect(try SevenZipArchive.carriesMetadata(commented))

            // describes this Mac, not the file: never packed, so nothing to carry
            let downloaded = try file("downloaded.txt")
            tag(downloaded, "com.apple.quarantine")
            #expect(try !SevenZipArchive.carriesMetadata(downloaded))

            // a filesystem flag no attribute mentions, carried as the FinderInfo one
            let hidden = try file("hidden.txt")
            #expect(chflags(hidden.path, UInt32(UF_HIDDEN)) == 0)
            #expect(try SevenZipArchive.carriesMetadata(hidden))

            let folder = dir.appendingPathComponent("folder")
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            #expect(try !SevenZipArchive.carriesMetadata(folder))
            tag(folder, "com.apple.FinderInfo.custom")
            #expect(try SevenZipArchive.carriesMetadata(folder))

            // the link itself is asked, not what it points at
            let link = dir.appendingPathComponent("link")
            try fm.createSymbolicLink(at: link, withDestinationURL: commented)
            #expect(try !SevenZipArchive.carriesMetadata(link))

            // not being able to tell is a failure, not "nothing"
            #expect(throws: (any Error).self) {
                _ = try SevenZipArchive.carriesMetadata(dir.appendingPathComponent("gone.txt"))
            }
        }
    }

    // MARK: - Compress without a window

    @MainActor struct CompressProgressTests {

        private func makeState(reportingTo center: ExtractionProgressCenter) -> ArchiveState {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.progressCenter = center
            return state
        }

        /// Finder's compress entries have no window to show progress in, so they
        /// go to the progress center: the window that comes up for a long
        /// extraction comes up for them as well.
        @Test func aCompressWithNoWindowShowsInTheProgressCenter() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let project = try makeProject(in: dir, files: 64)
            let dest = dir.appendingPathComponent("FileApex.zip")
            let center = ExtractionProgressCenter()
            let state = makeState(reportingTo: center)

            #expect(await state.compress([project], to: dest, showingProgress: true))

            #expect(center.jobs.count == 1)
            let job = try #require(center.jobs.first)
            #expect(job.kind == .compression)
            #expect(job.archiveName == "FileApex.zip")
            #expect(job.destination?.path == dir.path)
            #expect(job.state == .done, "\(job.state)")
            #expect(job.hasEngineProgress, "the writer's progress never reached the job")
            #expect(try systemZipList(dest).contains("FileApex/module0/build/out0/Class0.kt"))
        }

        /// Quick Compress and the start page show a row of their own for each
        /// archive, and stay out of the progress window.
        @Test func aCompressWithItsOwnRowStaysOutOfTheProgressCenter() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let project = try makeProject(in: dir, files: 16)
            let dest = dir.appendingPathComponent("FileApex.zip")
            let center = ExtractionProgressCenter()
            let state = makeState(reportingTo: center)

            #expect(await state.compress([project], to: dest))

            #expect(center.jobs.isEmpty)
            #expect(FileManager.default.fileExists(atPath: dest.path))
        }

        /// Cancel in the progress window stops the compress, and no archive is
        /// left behind under the name it was going to have.
        @Test func aCancelledCompressWritesNothing() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let project = try makeProject(in: dir, files: 2_000)
            let dest = dir.appendingPathComponent("FileApex.zip")
            let center = ExtractionProgressCenter()
            let state = makeState(reportingTo: center)

            let compressing = Task { await state.compress([project], to: dest, showingProgress: true) }
            // the job is there as soon as the compress starts
            for _ in 0..<1_000 where center.jobs.isEmpty { await Task.yield() }
            let job = try #require(center.jobs.first, "the compress never showed up in the progress center")
            center.requestCancel(job.id)

            #expect(await !compressing.value)
            #expect(center.jobs.first?.state == .cancelled, "\(String(describing: center.jobs.first?.state))")
            #expect(!FileManager.default.fileExists(atPath: dest.path), "a cancelled compress left an archive")
            #expect(state.error == nil, "cancelling is not an error: \(state.error ?? "")")
        }

        /// A compress from Finder that fails has nowhere else to say so: the job
        /// fails with the reason, which keeps the progress window up.
        @Test func aCompressThatFailsSaysWhy() async throws {
            let dir = try makeTempDir()
            let project = try makeProject(in: dir, files: 16)
            let locked = project.appendingPathComponent("module0/build")
            // Restored before the directory is removed, or the cleanup cannot
            // descend into it either.
            defer {
                chmod(locked.path, 0o755)
                try? FileManager.default.removeItem(at: dir)
            }
            #expect(chmod(locked.path, 0o000) == 0, "could not make the folder unreadable")
            let dest = dir.appendingPathComponent("FileApex.zip")
            let center = ExtractionProgressCenter()
            let state = makeState(reportingTo: center)

            #expect(await !state.compress([project], to: dest, showingProgress: true))

            guard case .failed(let reason) = center.jobs.first?.state else {
                Issue.record("the job did not fail: \(String(describing: center.jobs.first?.state))")
                return
            }
            #expect(reason.contains("build"), "\(reason)")
            #expect(!FileManager.default.fileExists(atPath: dest.path))
        }

        /// A read that fails for another reason than being cancelled says why: in
        /// `error`, and in the job of a compress that has no window. Swallowed, the
        /// add came back empty-handed and the job failed without a word, which
        /// the Finder's handler then took for a cancel.
        @Test func aReadThatFailsSaysWhy() async throws {
            struct DiskGone: LocalizedError {
                var errorDescription: String? { "The disk went away." }
            }
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let project = try makeProject(in: dir, files: 16)
            let dest = dir.appendingPathComponent("FileApex.zip")
            let center = ExtractionProgressCenter()
            let state = makeState(reportingTo: center)
            state.scanFiles = { _, _, _ in throw DiskGone() }

            #expect(await !state.compress([project], to: dest, showingProgress: true))

            #expect(state.error == "The disk went away.")
            #expect(center.jobs.first?.state == .failed("The disk went away."), "\(String(describing: center.jobs.first?.state))")
            #expect(!FileManager.default.fileExists(atPath: dest.path))
        }

        /// The quit warning and the window's name follow what is running:
        /// extraction while there is one, compression when that is all there is.
        @Test func whatIsRunningDecidesTheWording() {
            let center = ExtractionProgressCenter()
            #expect(center.runningKind == nil)

            let compress = center.begin(
                kind: .compression, archiveName: "a.zip", destination: nil, itemCount: 1, totalBytes: nil)
            #expect(center.runningKind == .compression)

            let extract = center.begin(archiveName: "b.zip", destination: nil, itemCount: 1, totalBytes: nil)
            #expect(center.jobs.last?.kind == .extraction)
            #expect(center.runningKind == .extraction)

            center.finish(extract, .done)
            #expect(center.runningKind == .compression)
            center.finish(compress, .cancelled)
            #expect(center.runningKind == nil)
        }
    }
}
