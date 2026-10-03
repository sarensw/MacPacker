import Foundation
import Testing
@testable import Core

extension AllCoreTests {
    struct ExtractionConflictTests {
        @Test func conflictChoicesPreserveExistingData() throws {
            let root = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            let target = root.appendingPathComponent("target")
            let staged = root.appendingPathComponent("staged")
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
            try Data("original".utf8).write(to: target.appendingPathComponent("same.txt"))
            try Data("incoming".utf8).write(to: staged.appendingPathComponent("same.txt"))
            try Data("added".utf8).write(to: staged.appendingPathComponent("new.txt"))
            #expect(throws: CancellationError.self) {
                _ = try ExtractionDestination.install(staged: staged, target: target, choice: .cancel)
            }
            #expect(try String(contentsOf: target.appendingPathComponent("same.txt"), encoding: .utf8) == "original")
            let result = try ExtractionDestination.install(staged: staged, target: target, choice: .merge)
            #expect(result.skippedExisting)
            #expect(try String(contentsOf: target.appendingPathComponent("same.txt"), encoding: .utf8) == "original")
            #expect(try String(contentsOf: target.appendingPathComponent("new.txt"), encoding: .utf8) == "added")
        }
        @Test func replaceKeepsOriginalsRecoverableAndNewFolderIsUnique() throws {
            let root = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            let target = root.appendingPathComponent("output")
            let staged = root.appendingPathComponent("staged")
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
            try Data("original".utf8).write(to: target.appendingPathComponent("old.txt"))
            try Data("new".utf8).write(to: staged.appendingPathComponent("new.txt"))
            var backup: URL?
            _ = try ExtractionDestination.install(staged: staged, target: target, choice: .replaceAll, folderIsOutput: true) { backup = $0 }
            #expect(try String(contentsOf: backup!.appendingPathComponent("output/old.txt"), encoding: .utf8) == "original")
            #expect(!FileManager.default.fileExists(atPath: target.appendingPathComponent("old.txt").path))
            try Data("separate".utf8).write(to: staged.appendingPathComponent("new.txt"))
            try FileManager.default.createDirectory(at: root.appendingPathComponent("output (2)"), withIntermediateDirectories: false)
            let result = try ExtractionDestination.install(staged: staged, target: target, choice: .newFolder)
            #expect(result.destination.lastPathComponent == "output (3)")
            #expect(try String(contentsOf: target.appendingPathComponent("new.txt"), encoding: .utf8) == "new")
        }
        @Test func mergeDoesNotFollowDestinationSymlinks() throws {
            let root = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            let target = root.appendingPathComponent("target")
            let staged = root.appendingPathComponent("staged")
            let outside = root.appendingPathComponent("outside")
            for url in [target, staged.appendingPathComponent("folder"), outside] {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
            try FileManager.default.createSymbolicLink(at: target.appendingPathComponent("folder"), withDestinationURL: outside)
            try Data("incoming".utf8).write(to: staged.appendingPathComponent("folder/new.txt"))
            let result = try ExtractionDestination.install(staged: staged, target: target, choice: .merge)
            #expect(result.skippedExisting)
            #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
        }
        @Test func failedInstallDoesNotOverwriteAnUnrelatedFile() throws {
            let root = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            let staged = root.appendingPathComponent("staged")
            let target = root.appendingPathComponent("not-a-directory")
            try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: false)
            try Data("original".utf8).write(to: target)
            try Data("new".utf8).write(to: staged.appendingPathComponent("new.txt"))
            #expect(throws: (any Error).self) {
                _ = try ExtractionDestination.install(staged: staged, target: target, choice: .merge)
            }
            #expect(try String(contentsOf: target, encoding: .utf8) == "original")
        }
    }
}
