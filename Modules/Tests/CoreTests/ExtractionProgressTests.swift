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

            center.reportEngineProgress(id, completed: 50, total: 0)

            #expect(center.jobs[0].completedBytes == 50)
            #expect(center.jobs[0].fractionCompleted == 0.25)
        }

        @Test func fractionIsNilWithoutTotal() {
            let center = ExtractionProgressCenter()
            let id = center.begin(archiveName: "a.zip", destination: nil, itemCount: 1, totalBytes: nil)

            center.reportEngineProgress(id, completed: 50, total: 0)

            #expect(center.jobs[0].fractionCompleted == nil)
        }

        @Test func fractionClampsToOne() {
            let center = ExtractionProgressCenter()
            let id = center.begin(archiveName: "a.zip", destination: nil, itemCount: 1, totalBytes: 100)

            center.reportEngineProgress(id, completed: 250, total: 0)

            #expect(center.jobs[0].fractionCompleted == 1.0)
        }

        @Test func finishDoneSnapsCompletedToTotal() {
            let center = ExtractionProgressCenter()
            let id = center.begin(archiveName: "a.zip", destination: nil, itemCount: 1, totalBytes: 100)
            center.reportEngineProgress(id, completed: 10, total: 0)

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
            center.reportEngineProgress(id, completed: 5, total: 0)

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

            center.reportEngineProgress(id, completed: 400, total: 1200, at: start.addingTimeInterval(0.4))

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
            center.reportEngineProgress(id, completed: 800, total: 1200, at: start.addingTimeInterval(1.2))
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
                center.reportEngineProgress(id, completed: Int64(i) * 150, total: 10_000, at: start.addingTimeInterval(Double(i) * 0.4))
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

            center.reportEngineProgress(id, completed: 500, total: 0, at: start.addingTimeInterval(0.4))
            // byte count shrinks (e.g. temp files moved away) — clamp to 0
            center.reportEngineProgress(id, completed: 100, total: 0, at: start.addingTimeInterval(0.8))

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
                center.reportEngineProgress(known, completed: Int64(i) * 100, total: 10_000, at: start.addingTimeInterval(Double(i) * 0.4))
                center.reportEngineProgress(unknown, completed: Int64(i) * 100, total: 0, at: start.addingTimeInterval(Double(i) * 0.4))
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

            center.reportEngineProgress(id, completed: 500, total: 1000, at: start.addingTimeInterval(1.0))

            // 500 bytes left at ~500 B/s current speed → about a second
            let remaining = center.jobs[0].estimatedSecondsRemaining
            #expect(remaining != nil)
            #expect(remaining! > 0 && remaining! < 5)

            // unknown total → no estimate
            let id2 = center.begin(archiveName: "b.zip", destination: nil, itemCount: 1, totalBytes: nil)
            center.reportEngineProgress(id2, completed: 500, total: 0, at: Date())
            #expect(center.jobs[1].estimatedSecondsRemaining == nil)
        }

        /// Finder's "Extract Here" on several archives opens each one before
        /// its job starts. No job is running then, and the action is not done:
        /// with the progress window as its last window, the app quit when that
        /// closed between two archives and left the rest unextracted (#279).
        @Test func anActionIsUnderWayBetweenItsJobs() async {
            let center = ExtractionProgressCenter()
            var underWayBetweenJobs = false

            await center.run {
                let first = center.begin(archiveName: "a.zip", destination: nil, itemCount: 1, totalBytes: nil)
                center.finish(first, .done)
                // the second archive is being opened: no job yet
                #expect(!center.hasActiveJobs)
                underWayBetweenJobs = center.isRunningAction
            }

            #expect(underWayBetweenJobs)
            #expect(!center.isRunningAction)
        }

        /// Two actions at once, each from its own Finder menu click: the first
        /// to end does not end the other.
        @Test func anActionStaysUnderWayWhenAnotherEnds() async {
            let center = ExtractionProgressCenter()
            var underWayAfterTheInnerOneEnded = false

            await center.run {
                await center.run {}
                underWayAfterTheInnerOneEnded = center.isRunningAction
            }

            #expect(underWayAfterTheInnerOneEnded)
            #expect(!center.isRunningAction)
        }

        /// A failed job stays listed until the window that shows it closes.
        /// The app must not quit under it: nobody would learn that the
        /// extraction failed.
        @Test func aFailedJobCountsUntilItIsCleared() {
            let center = ExtractionProgressCenter()
            let done = center.begin(archiveName: "a.zip", destination: nil, itemCount: 1, totalBytes: nil)
            center.finish(done, .done)
            let cancelled = center.begin(archiveName: "b.zip", destination: nil, itemCount: 1, totalBytes: nil)
            center.finish(cancelled, .cancelled)
            #expect(!center.hasFailedJobs)

            let failed = center.begin(archiveName: "c.zip", destination: nil, itemCount: 1, totalBytes: nil)
            center.finish(failed, .failed("disk full"))
            #expect(center.hasFailedJobs)

            center.clearFinished()
            #expect(!center.hasFailedJobs)
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

    // MARK: - Where a job is seen

    /// An archive window shows its own jobs at its foot while it is open; the
    /// progress window shows everything else — Finder's jobs, and a window's
    /// once that window has closed.
    @MainActor struct ExtractionJobWindowTests {

        @Test func aWindowShowsItsOwnJobsAndTheProgressWindowTheRest() {
            let center = ExtractionProgressCenter()
            let window = UUID()
            center.windowOpened(window)
            let own = center.begin(archiveName: "a.zip", destination: nil, shownIn: window, itemCount: 1, totalBytes: 10)
            let finders = center.begin(archiveName: "b.zip", destination: nil, itemCount: 1, totalBytes: 10)

            #expect(center.jobs(shownIn: window).map(\.id) == [own])
            #expect(center.windowlessJobs.map(\.id) == [finders])
            // and the app still knows of both, to warn before it quits
            #expect(center.jobs.count == 2)
        }

        @Test func aJobStillRunningWhenItsWindowClosesGoesToTheProgressWindow() {
            let center = ExtractionProgressCenter()
            let window = UUID()
            center.windowOpened(window)
            let running = center.begin(archiveName: "a.zip", destination: nil, shownIn: window, itemCount: 1, totalBytes: 10)
            let failed = center.begin(archiveName: "b.zip", destination: nil, shownIn: window, itemCount: 1, totalBytes: 10)
            center.finish(failed, .failed("CRC error"))

            center.windowClosed(window)

            // the failed one was seen where it ran, and goes with the window
            #expect(center.jobs.map(\.id) == [running])
            #expect(center.windowlessJobs.map(\.id) == [running])
        }

        /// A window that never said it was open shows nothing: its jobs are
        /// the progress window's.
        @Test func aJobOfAWindowNotOpenIsTheProgressWindows() {
            let center = ExtractionProgressCenter()
            let id = center.begin(archiveName: "a.zip", destination: nil, shownIn: UUID(), itemCount: 1, totalBytes: 10)
            #expect(center.windowlessJobs.map(\.id) == [id])
        }

        /// The progress window clears what it showed when it closes; a failed
        /// job an open window shows stays until that window puts it away.
        @Test func clearingTheProgressWindowLeavesTheWindowsJobs() {
            let center = ExtractionProgressCenter()
            let window = UUID()
            center.windowOpened(window)
            let own = center.begin(archiveName: "a.zip", destination: nil, shownIn: window, itemCount: 1, totalBytes: 10)
            let finders = center.begin(archiveName: "b.zip", destination: nil, itemCount: 1, totalBytes: 10)
            center.finish(own, .failed("CRC error"))
            center.finish(finders, .done)

            center.clearFinished()
            #expect(center.jobs.map(\.id) == [own])

            center.dismiss(own)
            #expect(center.jobs.isEmpty)
        }

        @Test func aRunningJobIsNotDismissed() {
            let center = ExtractionProgressCenter()
            let window = UUID()
            center.windowOpened(window)
            let id = center.begin(archiveName: "a.zip", destination: nil, shownIn: window, itemCount: 1, totalBytes: 10)
            center.dismiss(id)
            #expect(center.jobs.map(\.id) == [id])
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
                state.extract(items: [fileItem], to: dest, smart: false)
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
                state.extract(to: dest, smart: false)
            }

            // the full-archive extraction must actually produce files
            // (Archive7ZipEngine.extract(_:to:) used to be a no-op)
            let contents = try FileManager.default.contentsOfDirectory(at: dest, includingPropertiesForKeys: nil)
            #expect(!contents.isEmpty)

            #expect(center.jobs.count == 1)
            #expect(center.jobs[0].state == .done)
            #expect(center.hasActiveJobs == false)
        }

        /// A window's state marks its extractions as the window's own; one no
        /// window shows — Finder's — leaves them to the progress window.
        @Test(arguments: [true, false])
        func extractionsCarryTheirWindow(inWindow: Bool) async throws {
            let state = try await openedState()
            let center = ExtractionProgressCenter()
            state.progressCenter = center
            let window = inWindow ? UUID() : nil
            state.windowID = window

            let dest = try makeDest()
            defer { try? FileManager.default.removeItem(at: dest) }
            let fileItem = state.entries.values.first(where: { $0.type == .file && $0.uncompressedSize > 0 })!

            for run in [{ state.extract(items: [fileItem], to: dest, smart: false) },
                        { state.extract(to: dest, smart: false) }] {
                await withCheckedContinuation { continuation in
                    state.onStatusChange = { status in
                        if status == .done { continuation.resume() }
                    }
                    run()
                }
            }

            #expect(center.jobs.count == 2)
            #expect(center.jobs.allSatisfy { $0.shownIn == window })
        }
    }
}
