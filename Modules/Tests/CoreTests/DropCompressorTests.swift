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
    }
}
