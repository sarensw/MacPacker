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

        @Test func reportFillsUniformSlotPoints() {
            // 120 fixed positions across the transfer; crossing a slot
            // records the instantaneous speed at that moment — raw values,
            // no averaging or normalization
            let center = ExtractionProgressCenter()
            let id = center.begin(archiveName: "a.zip", destination: nil, itemCount: 1, totalBytes: 1200)
            let start = center.jobs[0].startedAt

            center.report(id, completedBytes: 400, at: start.addingTimeInterval(0.4))

            let third = center.jobs[0].speedSamples
            // origin + every slot boundary up to 400/1200 of the transfer
            #expect(third.count == 1 + ExtractionJob.maxSpeedSamples / 3)
            #expect(third.allSatisfy { abs($0.bytesPerSecond - 1000) < 1 })
            // slot positions are uniform and monotonic
            let positions = third.map(\.completedBytes)
            #expect(positions == positions.sorted())
            #expect(positions.first == 0)

            // a second report at a different speed fills its slots with the
            // causally smoothed speed — earlier points stay untouched
            center.report(id, completedBytes: 800, at: start.addingTimeInterval(1.2))
            let twoThirds = center.jobs[0].speedSamples
            #expect(Array(twoThirds.prefix(third.count)) == third)
            let smoothed = 500 * ExtractionJob.speedSmoothing + 1000 * (1 - ExtractionJob.speedSmoothing)
            #expect(abs(twoThirds.last!.bytesPerSecond - smoothed) < 1)
            #expect(abs(center.jobs[0].currentBytesPerSecond - smoothed) < 1)
        }

        @Test func slotPointsAreImmutableOnceRecorded() {
            let center = ExtractionProgressCenter()
            let id = center.begin(archiveName: "a.zip", destination: nil, itemCount: 1, totalBytes: 10_000)
            let start = center.jobs[0].startedAt

            var snapshots: [[ExtractionSpeedSample]] = []
            for i in 1...50 {
                center.report(id, completedBytes: Int64(i) * 150, at: start.addingTimeInterval(Double(i) * 0.4))
                snapshots.append(center.jobs[0].speedSamples)
            }
            // every earlier snapshot is a strict prefix of the final state
            let final = snapshots.last!
            for snapshot in snapshots {
                #expect(Array(final.prefix(snapshot.count)) == snapshot)
            }
        }

        @Test func speedSamplesNeverNegative() {
            let center = ExtractionProgressCenter()
            let id = center.begin(archiveName: "a.zip", destination: nil, itemCount: 1, totalBytes: nil)
            let start = center.jobs[0].startedAt

            center.report(id, completedBytes: 500, at: start.addingTimeInterval(0.4))
            // byte count shrinks (e.g. temp files moved away) — clamp to 0
            center.report(id, completedBytes: 100, at: start.addingTimeInterval(0.8))

            #expect(center.jobs[0].speedSamples.allSatisfy { $0.bytesPerSecond >= 0 })
        }

        @Test func speedSamplesStayBounded() {
            // with a known total the slot construction caps the points;
            // without one, points append per report up to the same cap
            let center = ExtractionProgressCenter()
            let known = center.begin(archiveName: "a.zip", destination: nil, itemCount: 1, totalBytes: 10_000)
            let unknown = center.begin(archiveName: "b.zip", destination: nil, itemCount: 1, totalBytes: nil)
            let start = center.jobs[0].startedAt

            for i in 1...1000 {
                center.report(known, completedBytes: Int64(i) * 100, at: start.addingTimeInterval(Double(i) * 0.4))
                center.report(unknown, completedBytes: Int64(i) * 100, at: start.addingTimeInterval(Double(i) * 0.4))
            }

            for job in center.jobs {
                #expect(job.speedSamples.count <= ExtractionJob.maxSpeedSamples + 1)
                let progress = job.speedSamples.map(\.completedBytes)
                #expect(progress == progress.sorted())
            }
        }

        @Test func remainingSecondsFromTotalAndSpeed() {
            let center = ExtractionProgressCenter()
            let id = center.begin(archiveName: "a.zip", destination: nil, itemCount: 1, totalBytes: 1000)
            let start = center.jobs[0].startedAt

            center.report(id, completedBytes: 500, at: start.addingTimeInterval(1.0))

            // 500 bytes left at ~500 B/s current speed → about a second
            let remaining = center.jobs[0].estimatedSecondsRemaining
            #expect(remaining != nil)
            #expect(remaining! > 0 && remaining! < 5)

            // unknown total → no estimate
            let id2 = center.begin(archiveName: "b.zip", destination: nil, itemCount: 1, totalBytes: nil)
            center.report(id2, completedBytes: 500, at: Date())
            #expect(center.jobs[1].estimatedSecondsRemaining == nil)
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

        @Test func ignoresFilesFromBeforeStart() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }

            // stale content (e.g. leftovers of a crashed previous run)
            // must not count
            try write(bytes: 10, to: dir.appendingPathComponent("existing.bin"))
            try await Task.sleep(for: .milliseconds(50))

            let watcher = ExtractionProgressWatcher(startedAt: Date())
            watcher.watch(dir)
            #expect(watcher.sampleCompletedBytes() == 0)

            let sub = dir.appendingPathComponent("sub")
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            try write(bytes: 15, to: dir.appendingPathComponent("new1.bin"))
            try write(bytes: 10, to: sub.appendingPathComponent("new2.bin"))

            let sampled = watcher.sampleCompletedBytes()
            #expect(sampled == 25)
        }

        @Test func countsOverwrittenStaleFiles() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }

            // previous run's output sitting at the destination
            try write(bytes: 100, to: dir.appendingPathComponent("big.bin"))
            try await Task.sleep(for: .milliseconds(50))

            let watcher = ExtractionProgressWatcher(startedAt: Date())
            watcher.watch(dir)
            #expect(watcher.sampleCompletedBytes() == 0)

            // re-extraction overwrites the stale file in place — its full
            // current size counts (a size delta would stay ≤ 0 here and
            // pin the progress bar)
            try write(bytes: 40, to: dir.appendingPathComponent("big.bin"))

            let sampled = watcher.sampleCompletedBytes()
            #expect(sampled == 40)
        }

        @Test func sampleSumsMultipleWatchedDirectories() async throws {
            let dirA = try makeTempDir()
            let dirB = try makeTempDir()
            defer {
                try? FileManager.default.removeItem(at: dirA)
                try? FileManager.default.removeItem(at: dirB)
            }

            let watcher = ExtractionProgressWatcher()
            watcher.watch(dirA)
            watcher.watch(dirB)

            try write(bytes: 7, to: dirA.appendingPathComponent("a.bin"))
            try write(bytes: 5, to: dirB.appendingPathComponent("b.bin"))

            let sampled = watcher.sampleCompletedBytes()
            #expect(sampled == 12)
        }

        @Test func sampleIsZeroForEmptyWatcher() async {
            let watcher = ExtractionProgressWatcher()
            let sampled = watcher.sampleCompletedBytes()
            #expect(sampled == 0)
        }
    }

    // MARK: - Engine progress (7zip bridge callback)

    struct EngineProgressTests {

        private final class ProgressCollector: @unchecked Sendable {
            private let lock = NSLock()
            private var _events: [(completed: Int64, total: Int64)] = []
            var events: [(completed: Int64, total: Int64)] {
                lock.lock(); defer { lock.unlock() }
                return _events
            }
            func add(_ completed: Int64, _ total: Int64) {
                lock.lock(); defer { lock.unlock() }
                _events.append((completed, total))
            }
        }

        private func makeDest() throws -> URL {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("EngineProgressTests_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        @Test func sevenZipExtractReportsByteProgress() async throws {
            let engine = Archive7ZipEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")
            let load = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })
            let files = load.items.values.filter { $0.type == .file }
            #expect(!files.isEmpty)

            let dest = try makeDest()
            defer { try? FileManager.default.removeItem(at: dest) }

            let collector = ProgressCollector()
            _ = try await engine.extract(
                items: Array(files),
                from: url,
                to: dest,
                passwordResolver: { _ in nil },
                onProgress: { completed, total in
                    collector.add(completed, total)
                    return true
                }
            )

            let events = collector.events
            #expect(!events.isEmpty)
            #expect(events.allSatisfy { $0.total > 0 })
            // completed values never go backwards
            let completed = events.map(\.completed)
            #expect(completed == completed.sorted())
            #expect(completed.last! <= events.last!.total)
        }

        @Test func xadExtractReportsByteProgress() async throws {
            let engine = ArchiveXadEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")
            let load = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })
            let files = load.items.values.filter { $0.type == .file && $0.uncompressedSize > 0 }
            #expect(!files.isEmpty)

            let dest = try makeDest()
            defer { try? FileManager.default.removeItem(at: dest) }

            let collector = ProgressCollector()
            _ = try await engine.extract(
                items: Array(files),
                from: url,
                to: dest,
                passwordResolver: { _ in nil },
                onProgress: { completed, total in
                    collector.add(completed, total)
                    return true
                }
            )

            let events = collector.events
            #expect(!events.isEmpty)
            #expect(events.allSatisfy { $0.total > 0 })
            let completed = events.map(\.completed)
            #expect(completed == completed.sorted())
        }

        @Test func xadAbortFromProgressCancelsExtraction() async throws {
            let engine = ArchiveXadEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")
            let load = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })
            let files = load.items.values.filter { $0.type == .file && $0.uncompressedSize > 0 }

            let dest = try makeDest()
            defer { try? FileManager.default.removeItem(at: dest) }

            await #expect(throws: CancellationError.self) {
                _ = try await engine.extract(
                    items: Array(files),
                    from: url,
                    to: dest,
                    passwordResolver: { _ in nil },
                    onProgress: { _, _ in false }
                )
            }
        }

        @Test func abortFromProgressCancelsExtraction() async throws {
            let engine = Archive7ZipEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")
            let load = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })
            let files = load.items.values.filter { $0.type == .file }

            let dest = try makeDest()
            defer { try? FileManager.default.removeItem(at: dest) }

            await #expect(throws: CancellationError.self) {
                _ = try await engine.extract(
                    items: Array(files),
                    from: url,
                    to: dest,
                    passwordResolver: { _ in nil },
                    onProgress: { _, _ in false }
                )
            }
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

        @Test func dragOutTracksJobAndDeliversFile() async throws {
            let state = try await openedState()
            let center = ExtractionProgressCenter()
            state.progressCenter = center

            let dest = try makeDest()
            defer { try? FileManager.default.removeItem(at: dest) }

            let fileItem = state.entries.values.first(where: { $0.type == .file && $0.uncompressedSize > 0 })!
            let target = dest.appendingPathComponent(fileItem.name)

            try await state.fulfillDrag(item: fileItem, to: target)

            #expect(FileManager.default.fileExists(atPath: target.path))
            #expect(center.jobs.count == 1)
            let job = center.jobs[0]
            #expect(job.state == .done)
            #expect(job.archiveName == "defaultArchive.zip")
            #expect(job.destination?.path == dest.path)
            #expect(job.itemCount == 1)
            #expect(job.totalBytes == Int64(fileItem.uncompressedSize))
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
