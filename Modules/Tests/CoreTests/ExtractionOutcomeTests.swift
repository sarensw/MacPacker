//
//  ExtractionOutcomeTests.swift
//  Modules
//
//  An extraction says how it ended — what the window waits for before it
//  selects the result in Finder or closes — and what it put in the folder can
//  be found again, whatever names it took there.
//

import Foundation
import Testing
@testable import Core

extension AllCoreTests {
    @MainActor struct ExtractionOutcomeTests {

        private func makeFolder() throws -> URL {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("ExtractionOutcomeTests_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        private func openedState() async throws -> ArchiveState {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.progressCenter = ExtractionProgressCenter()
            let folderURL = try #require(Bundle.module.url(forResource: "defaultArchives", withExtension: nil))
            state.open(url: folderURL.appendingPathComponent("defaultArchive.zip"))
            try await state.openTask?.value
            return state
        }

        @Test func aFinishedRunSaysSo() async throws {
            let dest = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dest) }
            let state = try await openedState()

            #expect(await state.extract(to: dest, smart: false).value == .done)
            let item = try #require(state.entries.values.first { $0.type == .file && $0.uncompressedSize > 0 })
            let other = try makeFolder()
            defer { try? FileManager.default.removeItem(at: other) }
            #expect(await state.extract(items: [item], to: other, smart: false).value == .done)
        }

        /// A destination that cannot be a folder: the run fails, and says so.
        @Test func aFailedRunSaysSo() async throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            let notAFolder = dir.appendingPathComponent("file")
            try Data("x".utf8).write(to: notAFolder)
            let state = try await openedState()

            let outcome = await state.extract(to: notAFolder.appendingPathComponent("inside"), smart: false).value
            if case .failed = outcome {} else {
                Issue.record("ended as \(outcome)")
            }
        }

        /// Cancel clicked as the engine finishes, or with one that never looks
        /// for it: the run still ends as cancelled, so nothing that follows it
        /// — moving the archive to the Trash, closing the window — acts as if
        /// it had finished.
        @Test(arguments: [false, true])
        func aCancelTheEngineMissedStillCancels(wholeArchive: Bool) async throws {
            let engine = EngineIgnoringCancel()
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: SelectorIgnoringCancel(engine: engine))
            let center = ExtractionProgressCenter()
            state.progressCenter = center
            let folderURL = try #require(Bundle.module.url(forResource: "defaultArchives", withExtension: nil))
            state.open(url: folderURL.appendingPathComponent("defaultArchive.zip"))
            try await state.openTask?.value
            let dest = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dest) }

            let run: Task<ExtractionJob.State, Never>
            if wholeArchive {
                run = state.extract(to: dest, smart: false)
            } else {
                let item = try #require(state.entries.values.first { $0.type == .file && $0.uncompressedSize > 0 })
                run = state.extract(items: [item], to: dest, smart: false)
            }
            // the engine is at work; Cancel now, then let it end normally
            await engine.hasStarted()
            let job = try #require(center.jobs.first)
            center.requestCancel(job.id)
            engine.letItEnd()

            #expect(await run.value == .cancelled)
        }

        // MARK: - What it put there

        @Test func whatIsNewIsWhatItPutThere() throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            try Data("mine".utf8).write(to: dir.appendingPathComponent("mine.txt"))
            let before = ExtractedItems.contents(of: dir)
            try FileManager.default.createDirectory(at: dir.appendingPathComponent("trip (2)"), withIntermediateDirectories: true)

            #expect(ExtractedItems.find(in: dir, before: before, names: ["trip"]).map(\.lastPathComponent) == ["trip (2)"])
        }

        /// Finder may write its `.DS_Store` into the folder meanwhile: hidden, it
        /// is not what the extraction put there.
        @Test func aHiddenFileIsNotWhatItPutThere() throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            let before = ExtractedItems.contents(of: dir)
            try Data().write(to: dir.appendingPathComponent(".DS_Store"))
            try FileManager.default.createDirectory(at: dir.appendingPathComponent("trip"), withIntermediateDirectories: true)

            #expect(ExtractedItems.find(in: dir, before: before, names: ["trip"]).map(\.lastPathComponent) == ["trip"])
        }

        /// Extracted over what was there: nothing is new, so it is the items of
        /// the names extracted — those that are there.
        @Test func overWhatWasThereItIsTheNamesExtracted() throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            try Data("new".utf8).write(to: dir.appendingPathComponent("a.txt"))
            let before = ExtractedItems.contents(of: dir)

            #expect(ExtractedItems.find(in: dir, before: before, names: ["a.txt", "gone.txt"]).map(\.lastPathComponent) == ["a.txt"])
        }

        /// Extracted over what was there, a hidden name among them: it is not
        /// taken for what was extracted either.
        @Test func overWhatWasThereAHiddenNameIsNotTaken() throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            try Data().write(to: dir.appendingPathComponent(".DS_Store"))
            try Data("new".utf8).write(to: dir.appendingPathComponent("a.txt"))
            let before = ExtractedItems.contents(of: dir)

            #expect(ExtractedItems.find(in: dir, before: before, names: [".DS_Store", "a.txt"]).map(\.lastPathComponent) == ["a.txt"])
        }

        @Test func extractingNextToTheArchiveIsOffUntilTurnedOn() {
            let defaults = isolatedDefaults()
            #expect(!Keys.extractNextToArchiveEnabled(in: defaults))
            defaults.set(true, forKey: Keys.extractNextToArchive)
            #expect(Keys.extractNextToArchiveEnabled(in: defaults))
        }
    }
}


/// An engine whose extractions wait until they are let go, then end normally
/// whether or not they were cancelled meanwhile: one that never looks at its
/// progress callback. Opening is 7-Zip's.
private final class EngineIgnoringCancel: ArchiveEngine, @unchecked Sendable {
    private let real = Archive7ZipEngine()
    private let started = AsyncStream<Void>.makeStream()
    private let gate = AsyncStream<Void>.makeStream()

    /// Returns once an extraction has begun.
    func hasStarted() async {
        for await _ in started.stream { return }
    }

    /// Lets the extraction that is waiting end.
    func letItEnd() {
        gate.continuation.yield()
    }

    private func work() async {
        started.continuation.yield()
        // a cancel ends the wait as well, and the extraction still ends normally
        for await _ in gate.stream { return }
    }

    func statusStream() async -> AsyncStream<EngineStatus> { await real.statusStream() }
    func cancel() async {}
    func loadArchive(url: URL, passwordResolver: @escaping ArchivePasswordResolver) async throws -> ArchiveEngineLoadResult {
        try await real.loadArchive(url: url, passwordResolver: passwordResolver)
    }
    func extract(items: [ArchiveItem], from url: URL, to destination: URL, passwordResolver: @escaping ArchivePasswordResolver) async throws -> ArchiveExtractionResult {
        let result = try await real.extract(items: items, from: url, to: destination, passwordResolver: passwordResolver)
        await work()
        return result
    }
    func extract(item: ArchiveItem, from url: URL, to destination: URL, passwordResolver: @escaping ArchivePasswordResolver) async throws -> URL {
        try await real.extract(item: item, from: url, to: destination, passwordResolver: passwordResolver)
    }
    func extract(_ url: URL, to destination: URL, passwordResolver: @escaping ArchivePasswordResolver) async throws {
        await work()
    }
}

private struct SelectorIgnoringCancel: ArchiveEngineSelectorProtocol {
    let engine: EngineIgnoringCancel
    func engine(for id: String) -> (any ArchiveEngine)? { engine }
    func engine(for type: ArchiveEngineType) -> any ArchiveEngine { engine }
    func engineType(for id: String) -> ArchiveEngineType? { .`7zip` }
}
