//
//  ExtractionProgressTests.swift
//  Modules
//
//  Created by Claude on 09.07.26.
//

import Testing
import Foundation
@testable import Core

extension AllCoreTests {

    // MARK: - ExtractionProgressCenter

    @MainActor struct ExtractionProgressCenterTests {

        @Test func beginAddsRunningJob() {
            let center = ExtractionProgressCenter()
            let id = center.begin(
                archiveName: "a.zip",
                destination: URL(fileURLWithPath: "/tmp/dest"),
                itemCount: 3,
                totalBytes: 100
            )

            #expect(center.jobs.count == 1)
            let job = center.jobs[0]
            #expect(job.id == id)
            #expect(job.archiveName == "a.zip")
            #expect(job.itemCount == 3)
            #expect(job.totalBytes == 100)
            #expect(job.completedBytes == 0)
            #expect(job.state == .running)
            #expect(center.hasActiveJobs)
        }

        @Test func reportUpdatesCompletedBytesAndFraction() {
            let center = ExtractionProgressCenter()
            let id = center.begin(archiveName: "a.zip", destination: nil, itemCount: 1, totalBytes: 200)

            center.report(id, completedBytes: 50)

            #expect(center.jobs[0].completedBytes == 50)
            #expect(center.jobs[0].fractionCompleted == 0.25)
        }

        @Test func fractionIsNilWithoutTotal() {
            let center = ExtractionProgressCenter()
            let id = center.begin(archiveName: "a.zip", destination: nil, itemCount: 1, totalBytes: nil)

            center.report(id, completedBytes: 50)

            #expect(center.jobs[0].fractionCompleted == nil)
        }

        @Test func fractionClampsToOne() {
            let center = ExtractionProgressCenter()
            let id = center.begin(archiveName: "a.zip", destination: nil, itemCount: 1, totalBytes: 100)

            center.report(id, completedBytes: 250)

            #expect(center.jobs[0].fractionCompleted == 1.0)
        }

        @Test func finishDoneSnapsCompletedToTotal() {
            let center = ExtractionProgressCenter()
            let id = center.begin(archiveName: "a.zip", destination: nil, itemCount: 1, totalBytes: 100)
            center.report(id, completedBytes: 10)

            center.finish(id, .done)

            #expect(center.jobs[0].state == .done)
            #expect(center.jobs[0].completedBytes == 100)
            #expect(center.hasActiveJobs == false)
        }

        @Test func finishIsTerminal() {
            let center = ExtractionProgressCenter()
            let id = center.begin(archiveName: "a.zip", destination: nil, itemCount: 1, totalBytes: 100)

            center.finish(id, .done)
            center.finish(id, .failed("boom"))
            center.report(id, completedBytes: 5)

            #expect(center.jobs[0].state == .done)
            #expect(center.jobs[0].completedBytes == 100)
        }

        @Test func requestCancelFiresHandlerOnce() {
            let center = ExtractionProgressCenter()
            let id = center.begin(archiveName: "a.zip", destination: nil, itemCount: 1, totalBytes: nil)
            var cancelCount = 0
            center.setOnCancel(id) { cancelCount += 1 }

            center.requestCancel(id)
            center.requestCancel(id)

            #expect(cancelCount == 1)
            // the job is not finished by the request itself — the extraction
            // task reports .cancelled once it actually stopped
            #expect(center.jobs[0].state == .running)

            center.finish(id, .cancelled)
            #expect(center.jobs[0].state == .cancelled)
        }

        @Test func clearFinishedKeepsRunningJobs() {
            let center = ExtractionProgressCenter()
            let done = center.begin(archiveName: "a.zip", destination: nil, itemCount: 1, totalBytes: nil)
            let running = center.begin(archiveName: "b.zip", destination: nil, itemCount: 1, totalBytes: nil)
            center.finish(done, .done)

            center.clearFinished()

            #expect(center.jobs.count == 1)
            #expect(center.jobs[0].id == running)
        }
    }

    // MARK: - ExtractionProgressWatcher

    struct ExtractionProgressWatcherTests {

        private func makeTempDir() throws -> URL {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("ExtractionProgressWatcherTests_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        private func write(bytes: Int, to url: URL) throws {
            try Data(repeating: 0x41, count: bytes).write(to: url)
        }

        @Test func sampleMeasuresBytesAddedAfterWatch() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }

            // pre-existing content must not count (baseline)
            try write(bytes: 10, to: dir.appendingPathComponent("existing.bin"))

            let watcher = ExtractionProgressWatcher()
            await watcher.watch(dir)

            let sub = dir.appendingPathComponent("sub")
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            try write(bytes: 15, to: dir.appendingPathComponent("new1.bin"))
            try write(bytes: 10, to: sub.appendingPathComponent("new2.bin"))

            let sampled = await watcher.sampleCompletedBytes()
            #expect(sampled == 25)
        }

        @Test func sampleSumsMultipleWatchedDirectories() async throws {
            let dirA = try makeTempDir()
            let dirB = try makeTempDir()
            defer {
                try? FileManager.default.removeItem(at: dirA)
                try? FileManager.default.removeItem(at: dirB)
            }

            let watcher = ExtractionProgressWatcher()
            await watcher.watch(dirA)
            await watcher.watch(dirB)

            try write(bytes: 7, to: dirA.appendingPathComponent("a.bin"))
            try write(bytes: 5, to: dirB.appendingPathComponent("b.bin"))

            let sampled = await watcher.sampleCompletedBytes()
            #expect(sampled == 12)
        }

        @Test func sampleIsZeroForEmptyWatcher() async {
            let watcher = ExtractionProgressWatcher()
            let sampled = await watcher.sampleCompletedBytes()
            #expect(sampled == 0)
        }
    }

    // MARK: - ArchiveState extraction reports jobs

    @MainActor struct ArchiveStateExtractProgressTests {

        private func openedState() async throws -> ArchiveState {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")
            state.open(url: url)
            try await state.openTask?.value
            return state
        }

        private func makeDest() throws -> URL {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("ExtractProgressTests_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        @Test func extractItemsTracksJobLifecycle() async throws {
            let state = try await openedState()
            let center = ExtractionProgressCenter()
            state.progressCenter = center

            let dest = try makeDest()
            defer { try? FileManager.default.removeItem(at: dest) }

            let fileItem = state.entries.values.first(where: { $0.type == .file && $0.uncompressedSize > 0 })!

            await withCheckedContinuation { continuation in
                state.onStatusChange = { status in
                    if status == .done { continuation.resume() }
                }
                state.extract(items: [fileItem], to: dest)
            }

            #expect(center.jobs.count == 1)
            let job = center.jobs[0]
            #expect(job.state == .done)
            #expect(job.archiveName == "defaultArchive.zip")
            #expect(job.totalBytes == Int64(fileItem.uncompressedSize))
            #expect(job.completedBytes == job.totalBytes)
            #expect(center.hasActiveJobs == false)
        }

        @Test func extractFullArchiveTracksJobAndProducesFiles() async throws {
            let state = try await openedState()
            let center = ExtractionProgressCenter()
            state.progressCenter = center

            let dest = try makeDest()
            defer { try? FileManager.default.removeItem(at: dest) }

            await withCheckedContinuation { continuation in
                state.onStatusChange = { status in
                    if status == .done { continuation.resume() }
                }
                state.extract(to: dest)
            }

            // the full-archive extraction must actually produce files
            // (Archive7ZipEngine.extract(_:to:) used to be a no-op)
            let contents = try FileManager.default.contentsOfDirectory(at: dest, includingPropertiesForKeys: nil)
            #expect(!contents.isEmpty)

            #expect(center.jobs.count == 1)
            #expect(center.jobs[0].state == .done)
            #expect(center.hasActiveJobs == false)
        }
    }
}
