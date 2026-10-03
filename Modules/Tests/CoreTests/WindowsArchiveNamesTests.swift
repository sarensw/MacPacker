import Foundation
import Testing
@testable import Swift7zip
@testable import Core

extension AllCoreTests {
    struct WindowsArchiveNamesTests {
        @Test func rejectsReservedAndInvalidNames() {
            let names = ["CON", "nul.txt", "LPT¹.log", "COM9", "trailing.", "space ", "bad:name", "a\\b", "a?b", "control\n", "/absolute", "../escape", "a//b"]
            for name in names {
                #expect(WindowsArchiveNames.conflicts(in: [(name, false)]) == [name])
            }
            #expect(WindowsArchiveNames.conflicts(in: [("café/report.txt", false), ("console.txt", false), ("COM10", false)]).isEmpty)
        }

        @Test func catchesCaseAndFileFolderCollisions() {
            for names in [[("Readme", false), ("README", false)],
                          [("Docs/a", false), ("docs/b", false)],
                          [("name", false), ("name/child", false)],
                          [("same", false), ("same", false)]] {
                #expect(!WindowsArchiveNames.conflicts(in: names).isEmpty)
            }
            #expect(WindowsArchiveNames.conflicts(in: [("docs", true), ("docs/a", false), ("docs/b", false)]).isEmpty)
        }

        @Test func refusesBeforeChangingDestinationAndReportsAllNames() throws {
            let root = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            let target = root.appendingPathComponent("existing.zip")
            let sentinel = Data("existing destination".utf8)
            try sentinel.write(to: target)
            do {
                try SevenZipArchive.writeArchive(destination: target, items: [
                    .addData(archivePath: "CON.txt", data: Data()),
                    .addData(archivePath: "bad:name", data: Data())
                ], options: .init(format: .zip, requireWindowsCompatibleNames: true))
                Issue.record("Expected incompatible names to stop the write")
            } catch {
                #expect(error.localizedDescription.contains("CON.txt"))
                #expect(error.localizedDescription.contains("bad:name"))
            }
            #expect(try Data(contentsOf: target) == sentinel)
        }

        @Test func checksKeptEntriesAndRenamesBeforeSaving() throws {
            let root = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            let source = root.appendingPathComponent("source.zip")
            let target = root.appendingPathComponent("copy.zip")
            // The opt-out must still allow names that are valid on macOS.
            try SevenZipArchive.writeArchive(destination: source, items: [
                .addData(archivePath: "bad:name", data: Data("contents".utf8))
            ], options: .init(format: .zip))
            let original = try Data(contentsOf: source)
            #expect(throws: (any Error).self) {
                try SevenZipArchive.writeArchive(source: source, destination: target, items: [],
                    options: .init(format: .zip, requireWindowsCompatibleNames: true))
            }
            #expect(!FileManager.default.fileExists(atPath: target.path))
            #expect(try Data(contentsOf: source) == original)
            let entry = try #require(SevenZipArchive(url: source).entries.first)
            try SevenZipArchive.writeArchive(source: source, destination: target,
                items: [.move(sourceIndex: entry.index, newPath: "safe.txt")],
                options: .init(format: .zip, requireWindowsCompatibleNames: true))
            #expect(try SevenZipArchive(url: target).entries.map(\.path) == ["safe.txt"])
        }

        @Test func optionIsOffByDefaultAndFollowsItsParent() {
            let defaults = isolatedDefaults()
            let options = CompressionOptions(format: .zip)
            defaults.set(true, forKey: Keys.requireWindowsCompatibleNames)
            #expect(!ArchiveSaveOptions.applyingFilePreferences(to: options, in: defaults).requireWindowsCompatibleNames)
            defaults.set(true, forKey: Keys.excludeMacMetadata)
            #expect(ArchiveSaveOptions.applyingFilePreferences(to: options, in: defaults).requireWindowsCompatibleNames)
            defaults.set(false, forKey: Keys.excludeMacMetadata)
            #expect(!ArchiveSaveOptions.applyingFilePreferences(to: options, in: defaults).requireWindowsCompatibleNames)
        }
    }
}
