//
//  DropCompressorTests.swift
//  Modules
//
//  Quick Compress's writing, without its window: one drop, one archive, and
//  the file the job reports for Finder to show.
//

import Testing
import Foundation
import Swift7zip
@testable import Core

extension AllCoreTests {

    @MainActor struct DropCompressorTests {

        /// The job names the file it wrote: the archive, or its first volume when
        /// it was split. There is no `noise.zip` then, and Finder could not show it.
        @Test(arguments: [nil, 64 << 10] as [UInt64?])
        func aDropReportsTheFileItWrote(volumeSize: UInt64?) async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let file = dir.appendingPathComponent("noise.bin")
            try noise(bytes: 200_000).write(to: file)
            let compressor = DropCompressor(
                catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip(),
                folderAccess: { _ in true })

            let job = try #require(compressor.compress(
                files: [file], options: .init(format: .zip, volumeSize: volumeSize)))
            await job.task?.value

            guard case .done(let written) = job.outcome else {
                Issue.record("the drop did not finish: \(job.outcome)")
                return
            }
            #expect(written.lastPathComponent == (volumeSize == nil ? "noise.zip" : "noise.zip.001"))
            #expect(FileManager.default.fileExists(atPath: written.path), "\(written.lastPathComponent) is not there")
        }

        /// A folder that can't be read fails the job, and nothing is written.
        /// It used to be skipped: the save went ahead without it and reported
        /// done, which for a single selected folder meant an empty 22-byte zip
        /// passing for its archive (#278). Locked by permissions here; under
        /// the sandbox the refusal is the same error.
        @Test(arguments: ["FileApex", "FileApex/build"])
        func aFolderThatCannotBeReadFailsTheJob(locked lockedPath: String) async throws {
            let dir = try makeTempDir()
            let project = dir.appendingPathComponent("FileApex")
            let build = project.appendingPathComponent("build")
            try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
            try "fun main() {}".write(to: project.appendingPathComponent("Main.kt"), atomically: true, encoding: .utf8)
            try "output".write(to: build.appendingPathComponent("app.jar"), atomically: true, encoding: .utf8)
            let locked = dir.appendingPathComponent(lockedPath)

            // Restored before the directory is removed, or the cleanup cannot
            // descend into it either.
            defer {
                chmod(locked.path, 0o755)
                try? FileManager.default.removeItem(at: dir)
            }
            #expect(chmod(locked.path, 0o000) == 0, "could not make the folder unreadable")
            let compressor = DropCompressor(
                catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip(),
                folderAccess: { _ in true })

            let job = try #require(compressor.compress(files: [project], options: .init(format: .zip)))
            await job.task?.value

            guard case .failed = job.outcome else {
                Issue.record("the job passed for done: \(job.outcome)")
                return
            }
            let archive = dir.appendingPathComponent("FileApex.zip")
            #expect(!FileManager.default.fileExists(atPath: archive.path),
                    "an archive without \(locked.lastPathComponent) was written")
        }
    }
}
