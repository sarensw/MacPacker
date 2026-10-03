import Foundation
import Testing
import ArchiveCommands
@testable import Core

extension AllCoreTests {
    struct ArchiveCommandTests {
        @Test func rejectsUnsafeOrAmbiguousOptions() {
            for arguments in [["create", "x.7z"], ["extract", "x.rar"], ["rename", "x.7z", "one"], ["list", "x.rar", "--password", "secret"], ["create", "x.tar", "file", "--encrypt-names"], ["update", "x.7z", "file", "--volume-size", "10m"], ["list", "x.rar", "--ask-password", "--password-stdin"]] {
                #expect(throws: (any Error).self) { try ArchiveCommand(arguments: arguments) }
            }
        }
        @Test func parsesVolumesAndLiteralPaths() throws {
            let command = try ArchiveCommand(arguments: ["create", "out.7z", "--volume-size", "100m", "--", "-input"])
            #expect(command.volumeSize == 104_857_600)
            #expect(command.operands == ["-input"])
            for invalid in ["0", "-1", "100x", "18446744073709551615g"] {
                #expect(throws: (any Error).self) { try ArchiveCommand.bytes(invalid) }
            }
        }
        @Test func volumePathsPreservePadding() {
            for (part, expected) in [("set.part03.rar", "set.part01.rar"), ("set.r02", "set.rar"), ("set.7z.003", "set.7z.001"), ("set.tar.002", "set.tar.001"), ("ordinary.rar", "ordinary.rar")] {
                #expect(VolumePath.first(URL(fileURLWithPath: "/tmp/\(part)")).lastPathComponent == expected)
            }
        }
        @Test func cleanupRefusesAChangedSource() throws {
            let directory = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: directory) }
            let source = directory.appendingPathComponent("source.rar")
            let fixture = Bundle.module.resourceURL!.appendingPathComponent("defaultArchives/defaultArchive.rar")
            try FileManager.default.copyItem(at: fixture, to: source)
            let cleanup = try ExtractionSourceCleanup(source: source, catalog: ArchiveTypeCatalog())
            try FileManager.default.removeItem(at: source)
            var removed = false
            #expect(throws: (any Error).self) { try cleanup.perform { _ in removed = true } }
            #expect(!removed)
        }
        @Test func cleanupOnlySelectsItsOwnLegacyVolumes() throws {
            let directory = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: directory) }
            let fixture = Bundle.module.resourceURL!.appendingPathComponent("defaultArchives/defaultArchive.rar")
            // Names exercise cleanup planning only, never archive parsing.
            for name in ["one.rar", "one.r00", "one.r01", "other.rar", "other.r00"] {
                try FileManager.default.copyItem(at: fixture, to: directory.appendingPathComponent(name))
            }
            let cleanup = try ExtractionSourceCleanup(source: directory.appendingPathComponent("one.rar"), catalog: ArchiveTypeCatalog())
            #expect(Set(cleanup.sources.map(\.lastPathComponent)) == ["one.rar", "one.r00", "one.r01"])
            var moved: [URL] = []
            try cleanup.perform { moved.append($0) }
            #expect(moved.count == 3)
        }
    }
}
