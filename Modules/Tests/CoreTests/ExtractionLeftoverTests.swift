//
//  ExtractionLeftoverTests.swift
//  Modules
//
//  A whole-archive extraction that does not finish — cancelled, failed, or left
//  at the password prompt — must leave the destination as it found it:
//  `ArchiveState.extract(to:smart:)` used to hand the destination itself to the
//  engine, so whatever was written by then stayed, and so did the container
//  folder smart extraction had created for it.
//
//  One that does finish must end up exactly where it did before: same layout,
//  same overwriting of what is already there, nothing extra left behind.
//
//  Fixtures are zips built at test time with the system `zip` CLI, as in
//  `SmartExtractionTests` — it is the layout that matters here, not a format.
//

import Foundation
import Testing
@testable import Core

/// How an extraction that does not finish can end.
enum UnfinishedEnding: Sendable, CaseIterable {
    case cancelled, failed, passwordCancelled

    var error: Error {
        switch self {
        case .cancelled: CancellationError()
        case .failed: ArchiveError.extractionFailed("CRC error")
        case .passwordCancelled: ArchiveError.passwordCancelled
        }
    }
}

/// 7-Zip for everything, except that an extraction ends the way the test asks
/// once every file is written — so the run stops with files on disk, as a real
/// one does when it is cancelled half-way or meets a damaged entry, but at a
/// point the test does not have to race for.
private struct EndingEngine: ArchiveEngine {
    let real = Archive7ZipEngine()
    let ending: UnfinishedEnding
    /// Where a whole-archive extraction was told to write.
    let handed = HandedFolder()

    func statusStream() async -> AsyncStream<EngineStatus> { await real.statusStream() }
    func cancel() async { await real.cancel() }

    func loadArchive(
        url: URL,
        passwordResolver: @escaping ArchivePasswordResolver
    ) async throws -> ArchiveEngineLoadResult {
        try await real.loadArchive(url: url, passwordResolver: passwordResolver)
    }

    func extract(
        items: [ArchiveItem],
        from url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver
    ) async throws -> ArchiveExtractionResult {
        _ = try await real.extract(items: items, from: url, to: destination, passwordResolver: passwordResolver)
        throw ending.error
    }

    func extract(
        _ url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver
    ) async throws {
        handed.set(destination)
        try await real.extract(url, to: destination, passwordResolver: passwordResolver)
        throw ending.error
    }
}

private final class HandedFolder: @unchecked Sendable {
    private let lock = NSLock()
    private var url: URL?

    func set(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        self.url = url
    }

    var value: URL? {
        lock.lock()
        defer { lock.unlock() }
        return url
    }
}

/// 7-Zip, whose whole-archive extraction finishes — and says so just before it
/// returns, so that a test can have something happen at that very moment.
private struct FinishingEngine: ArchiveEngine {
    let real = Archive7ZipEngine()
    let beforeReturning: @Sendable () async -> Void

    func statusStream() async -> AsyncStream<EngineStatus> { await real.statusStream() }
    func cancel() async { await real.cancel() }

    func loadArchive(
        url: URL,
        passwordResolver: @escaping ArchivePasswordResolver
    ) async throws -> ArchiveEngineLoadResult {
        try await real.loadArchive(url: url, passwordResolver: passwordResolver)
    }

    func extract(
        items: [ArchiveItem],
        from url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver
    ) async throws -> ArchiveExtractionResult {
        try await real.extract(items: items, from: url, to: destination, passwordResolver: passwordResolver)
    }

    func extract(
        _ url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver
    ) async throws {
        try await real.extract(url, to: destination, passwordResolver: passwordResolver)
        await beforeReturning()
    }
}

private struct EndingEngineSelector: ArchiveEngineSelectorProtocol {
    let engine: any ArchiveEngine

    func engine(for id: String) -> (any ArchiveEngine)? { engine }
    func engine(for type: ArchiveEngineType) -> any ArchiveEngine { engine }
    func engineType(for id: String) -> ArchiveEngineType? { .`7zip` }
}

extension AllCoreTests {
    @MainActor struct ExtractionLeftoverTests {

        private func makeFolder() throws -> URL {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("ExtractionLeftoverTests_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        /// Builds `<name>.zip` in `dir` from the given entries (a trailing `/`
        /// makes a folder), using the system `zip` CLI. Each file holds its own
        /// entry name, so a test can tell where a file on disk came from.
        private func makeZip(in dir: URL, name: String, entries: [String]) throws -> URL {
            let src = dir.appendingPathComponent("src-\(name)")
            for entry in entries {
                let path = src.appendingPathComponent(entry)
                if entry.hasSuffix("/") {
                    try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
                } else {
                    try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try Data(entry.utf8).write(to: path)
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

        /// Everything below `folder`, hidden items included, as sorted relative
        /// paths — folders with a trailing `/`.
        private func everything(in folder: URL) throws -> [String] {
            try FileManager.default.subpathsOfDirectory(atPath: folder.path).map { path in
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: folder.appendingPathComponent(path).path, isDirectory: &isDirectory)
                return isDirectory.boolValue ? path + "/" : path
            }.sorted()
        }

        private func text(_ url: URL) throws -> String {
            String(decoding: try Data(contentsOf: url), as: UTF8.self)
        }

        /// Opens the archive and runs `state.extract(to:smart:)` to its end,
        /// whatever that end is.
        private func extractFull(_ state: ArchiveState, _ url: URL, to dest: URL, smart: Bool) async throws {
            state.open(url: url)
            try await state.openTask?.value
            await withCheckedContinuation { continuation in
                state.onStatusChange = { status in
                    if status == .done { continuation.resume() }
                }
                state.extract(to: dest, smart: smart)
            }
        }

        // MARK: - An extraction that does not finish

        /// With smart extraction on, three top-level entries go into a `trip/`
        /// container; off, they go straight into the destination. Either way
        /// the engine has written all of them when the run ends unfinished, and
        /// none of it may stay — nor the container, nor anything of ours.
        @Test(arguments: UnfinishedEnding.allCases, [true, false])
        func anUnfinishedExtractionLeavesTheDestinationAsItWas(ending: UnfinishedEnding, smart: Bool) async throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            let zip = try makeZip(in: dir, name: "trip", entries: ["a.txt", "b.txt", "photos/c.jpg"])
            let dest = dir.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            try Data("mine".utf8).write(to: dest.appendingPathComponent("mine.txt"))

            let center = ExtractionProgressCenter()
            let state = ArchiveState(
                catalog: ArchiveTypeCatalog(),
                engineSelector: EndingEngineSelector(engine: EndingEngine(ending: ending)))
            state.progressCenter = center
            try await extractFull(state, zip, to: dest, smart: smart)

            #expect(try everything(in: dest) == ["mine.txt"])
            #expect(try text(dest.appendingPathComponent("mine.txt")) == "mine")
            // and it is still reported for what it was
            #expect(center.jobs.count == 1)
            #expect(center.jobs.first?.state != .done)
        }

        /// What the engine writes into meanwhile is one item in the destination,
        /// under the archive's name — the one Finder shows the run on.
        @Test func theEngineWritesIntoAWorkFolderNamedAfterTheArchive() async throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            let zip = try makeZip(in: dir, name: "trip", entries: ["a.txt", "b.txt"])
            let dest = dir.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

            let engine = EndingEngine(ending: .cancelled)
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: EndingEngineSelector(engine: engine))
            try await extractFull(state, zip, to: dest, smart: true)

            let handed = try #require(engine.handed.value)
            #expect(handed.lastPathComponent == "trip.macpack")
            #expect(handed.deletingLastPathComponent().resolvingSymlinksInPath().path == dest.resolvingSymlinksInPath().path)
            #expect(try everything(in: dest) == [])
        }

        /// What an unfinished run was about to overwrite is still the old file:
        /// nothing reaches the destination before the extraction has succeeded.
        @Test func anUnfinishedExtractionOverwritesNothing() async throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            let zip = try makeZip(in: dir, name: "photos", entries: ["photos/a.jpg", "photos/b.jpg"])
            let dest = dir.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: dest.appendingPathComponent("photos"), withIntermediateDirectories: true)
            try Data("old".utf8).write(to: dest.appending(path: "photos/a.jpg"))

            let state = ArchiveState(
                catalog: ArchiveTypeCatalog(),
                engineSelector: EndingEngineSelector(engine: EndingEngine(ending: .failed)))
            try await extractFull(state, zip, to: dest, smart: true)

            #expect(try everything(in: dest) == ["photos/", "photos/a.jpg"])
            #expect(try text(dest.appending(path: "photos/a.jpg")) == "old")
        }

        /// The real engine, stopped the way the progress window's cancel button
        /// stops it — here before it has written anything, which used to leave
        /// the empty container folder behind.
        @Test func cancellingAtOnceLeavesNoContainerFolder() async throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            let zip = try makeZip(in: dir, name: "trip", entries: ["a.txt", "b.txt", "photos/c.jpg"])
            let dest = dir.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

            let center = ExtractionProgressCenter()
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.progressCenter = center
            state.open(url: zip)
            try await state.openTask?.value

            await withCheckedContinuation { continuation in
                state.onStatusChange = { status in
                    if status == .done { continuation.resume() }
                }
                state.extract(to: dest, smart: true)
                if let job = center.jobs.first { center.requestCancel(job.id) }
            }

            #expect(center.jobs.first?.state == .cancelled)
            #expect(try everything(in: dest) == [])
        }

        /// "Extract selected" with the whole archive selected goes through a
        /// temp folder already, so no file of an unfinished run reaches the
        /// destination — but the container folder smart extraction makes for
        /// the result was created up front, and stayed.
        @Test(arguments: UnfinishedEnding.allCases)
        func anUnfinishedExtractSelectedLeavesNoContainerFolder(ending: UnfinishedEnding) async throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            let zip = try makeZip(in: dir, name: "trip", entries: ["a.txt", "b.txt", "photos/c.jpg"])
            let dest = dir.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            try Data("mine".utf8).write(to: dest.appendingPathComponent("mine.txt"))

            let state = ArchiveState(
                catalog: ArchiveTypeCatalog(),
                engineSelector: EndingEngineSelector(engine: EndingEngine(ending: ending)))
            state.open(url: zip)
            try await state.openTask?.value
            let topLevel = state.root?.children?.compactMap { state.entries[$0] } ?? []
            #expect(topLevel.count == 3)

            await withCheckedContinuation { continuation in
                state.onStatusChange = { status in
                    if status == .done { continuation.resume() }
                }
                state.extract(items: topLevel, to: dest, smart: true)
            }

            #expect(try everything(in: dest) == ["mine.txt"])
        }

        /// Cancel pressed as the engine writes its last byte: it has nothing
        /// left to stop, and returns as if all were well. The run was cancelled
        /// all the same, before anything of it reached the destination — so
        /// nothing does, and it is reported for what it was.
        @Test func aCancelThatArrivesAsTheEngineFinishesStillCancels() async throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            let zip = try makeZip(in: dir, name: "trip", entries: ["a.txt", "b.txt", "photos/c.jpg"])
            let dest = dir.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            try Data("mine".utf8).write(to: dest.appendingPathComponent("mine.txt"))

            let center = ExtractionProgressCenter()
            let engine = FinishingEngine(beforeReturning: {
                await MainActor.run {
                    if let job = center.jobs.first { center.requestCancel(job.id) }
                }
            })
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: EndingEngineSelector(engine: engine))
            state.progressCenter = center
            try await extractFull(state, zip, to: dest, smart: true)

            #expect(center.jobs.first?.state == .cancelled)
            #expect(try everything(in: dest) == ["mine.txt"])
        }

        // MARK: - An extraction that finishes

        /// Nothing of the way there is left once the result is in place —
        /// hidden items included.
        @Test(arguments: [true, false])
        func aFinishedExtractionLeavesOnlyItsResult(smart: Bool) async throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            let zip = try makeZip(in: dir, name: "trip", entries: ["a.txt", "b.txt", "photos/c.jpg"])
            let dest = dir.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            try await extractFull(state, zip, to: dest, smart: smart)

            let expected = smart
                ? ["trip/", "trip/a.txt", "trip/b.txt", "trip/photos/", "trip/photos/c.jpg"]
                : ["a.txt", "b.txt", "photos/", "photos/c.jpg"]
            #expect(try everything(in: dest) == expected)
            // …and nothing of the result still carries the mark Finder dims an
            // unfinished item for.
            for path in expected {
                let created = try FileManager.default.attributesOfItem(atPath: dest.appending(path: path).path)[.creationDate] as? Date
                #expect(created != ExtractionStaging.busyDate, "\(path)")
            }
        }

        /// Extracting over what is already there still does what it did: a file
        /// of the same name is overwritten, a folder of the same name is
        /// extracted into, and what the archive does not hold is left alone.
        /// (Whether to ask first is #140 — not decided here.)
        @Test(arguments: [ArchiveEngineType.`7zip`, .xad])
        func aFinishedExtractionStillOverwritesAndMerges(engine: ArchiveEngineType) async throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            let zip = try makeZip(in: dir, name: "photos", entries: ["photos/a.jpg", "photos/sub/b.jpg", "photos/new/c.jpg"])
            let dest = dir.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: dest.appending(path: "photos/sub"), withIntermediateDirectories: true)
            try Data("old".utf8).write(to: dest.appending(path: "photos/a.jpg"))
            try Data("mine".utf8).write(to: dest.appending(path: "photos/mine.txt"))
            try Data("mine too".utf8).write(to: dest.appending(path: "photos/sub/mine.txt"))

            let selector: ArchiveEngineSelectorProtocol = engine == .xad ? ArchiveEngineSelectorXad() : ArchiveEngineSelector7zip()
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: selector)
            try await extractFull(state, zip, to: dest, smart: true)

            #expect(try everything(in: dest) == [
                "photos/", "photos/a.jpg", "photos/mine.txt",
                "photos/new/", "photos/new/c.jpg",
                "photos/sub/", "photos/sub/b.jpg", "photos/sub/mine.txt",
            ])
            #expect(try text(dest.appending(path: "photos/a.jpg")) == "photos/a.jpg")
            #expect(try text(dest.appending(path: "photos/mine.txt")) == "mine")
            #expect(try text(dest.appending(path: "photos/sub/mine.txt")) == "mine too")
        }

        /// A container folder never lands on a folder that is already there: it
        /// takes the next free name, as before, and the existing one is not
        /// touched.
        @Test func aContainerNextToAFolderOfItsNameGetsANumber() async throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            let zip = try makeZip(in: dir, name: "trip", entries: ["a.txt", "b.txt"])
            let dest = dir.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: dest.appendingPathComponent("trip"), withIntermediateDirectories: true)
            try Data("mine".utf8).write(to: dest.appending(path: "trip/mine.txt"))

            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            try await extractFull(state, zip, to: dest, smart: true)

            #expect(try everything(in: dest) == ["trip (2)/", "trip (2)/a.txt", "trip (2)/b.txt", "trip/", "trip/mine.txt"])
        }
    }
}
