import Foundation
import Testing
@testable import Core

extension AllCoreTests {
    @MainActor struct FinderOperationProgressTests {
        @Test func savingAnArchiveReportsProgressAndCompletion() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let center = ExtractionProgressCenter()
            state.progressCenter = center
            let source = Bundle.module.resourceURL!.appendingPathComponent("defaultArchiveContent/hello world.txt")
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            state.create()
            state.add(url: source)
            let task = try #require(state.save(to: directory.appendingPathComponent("saved.zip")))
            #expect(center.hasActiveJobs, "Finder compression needs feedback before the write finishes")
            await task.value
            let job = try #require(center.jobs.first)
            #expect(job.state == .done)
            #expect(!center.hasActiveJobs)
            #expect(state.error == nil)
            #expect(!job.isCancellable, "Do not offer cancellation until saving can clean up partial output")
        }

        @Test func aFailedSaveKeepsItsErrorInTheProgressCenter() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let center = ExtractionProgressCenter()
            state.progressCenter = center
            state.create()
            state.add(url: Bundle.module.resourceURL!.appendingPathComponent("defaultArchiveContent/hello world.txt"))
            let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "/missing/archive.zip")
            await state.save(to: target)?.value
            let job = try #require(center.jobs.first)
            guard case .failed = job.state else {
                Issue.record("Expected a visible failure for an unwritable destination")
                return
            }
            #expect(!center.hasActiveJobs)
            #expect(state.error != nil)
        }
    }
}
