import Foundation
import Testing
import Swift7zip
@testable import Core

extension AllCoreTests {
    @MainActor struct ArchiveToolsTests {
        @Test func tarSaveProducesTarRatherThanZip() async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.progressCenter = ExtractionProgressCenter()
            state.create()
            state.add(url: Bundle.module.resourceURL!.appendingPathComponent("defaultArchiveContent/hello world.txt"))
            let target = directory.appendingPathComponent("saved.tar")
            await state.save(to: target)?.value
            #expect(state.error == nil)
            let bytes = try Data(contentsOf: target)
            try #require(bytes.count >= 262)
            #expect(String(data: bytes[257..<262], encoding: .ascii) == "ustar")
            #expect(try SevenZipArchive(url: target).entries.contains { $0.path == "hello world.txt" })
        }

        @Test func rarVolumesResolveWithoutJoiningFiles() throws {
            let detector = ArchiveTypeDetector(catalog: ArchiveTypeCatalog())
            for (part, first) in [("archive.r00", "archive.rar"), ("archive.r99", "archive.rar"), ("archive.part07.rar", "archive.part01.rar"), ("archive.part123.rar", "archive.part001.rar")] {
                let url = URL(fileURLWithPath: "/tmp/\(part)")
                let split = try #require(detector.detect(for: url)?.split)
                #expect(SplitVolumeResolver.firstVolume(for: url, split: split).lastPathComponent == first)
            }
        }
    }
}
