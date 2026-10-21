import Foundation
import Testing
@testable import Core

extension AllCoreTests {
    struct OneClickExtractionTests {
        @Test func missingOrUnknownDestinationUsesArchiveFolder() throws {
            let suite = "OneClickExtractionTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }

            #expect(OneClickExtractionDestination.saved(in: defaults) == .archiveFolder)
            defaults.set("unknown", forKey: Keys.oneClickExtractionDestination)
            #expect(OneClickExtractionDestination.saved(in: defaults) == .archiveFolder)

            defaults.set(OneClickExtractionDestination.chooseFolder.rawValue,
                         forKey: Keys.oneClickExtractionDestination)
            defaults.set(false, forKey: Keys.oneClickExtraction)
            #expect(OneClickExtractionDestination.saved(in: defaults) == .chooseFolder)
        }

        @Test func explicitDestinationsAndCompoundNames() throws {
            let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let archive = parent.appendingPathComponent("Photos.TAR.GZ")
            let detector = ArchiveTypeDetector(catalog: ArchiveTypeCatalog())

            #expect(OneClickExtractionDestination.sameFolder.directory(for: archive, detector: detector)?.path == parent.path)
            #expect(OneClickExtractionDestination.archiveFolder.directory(for: archive, detector: detector)?.lastPathComponent == "Photos")
            #expect(OneClickExtractionDestination.chooseFolder.directory(for: archive, detector: detector) == nil)
            #expect(!FileManager.default.fileExists(atPath: parent.path), "Resolving a destination must not create it")
        }

        @Test func namedFolderPreservesExistingOutput() throws {
            let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: parent.appendingPathComponent("Photos (2)"), withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: parent) }
            // A file as well as a directory can occupy the desired folder name.
            try Data("keep me".utf8).write(to: parent.appendingPathComponent("Photos"))

            let destination = OneClickExtractionDestination.archiveFolder.directory(
                for: parent.appendingPathComponent("Photos.ZIP"),
                detector: ArchiveTypeDetector(catalog: ArchiveTypeCatalog()))

            #expect(destination?.lastPathComponent == "Photos (3)")
            #expect(try Data(contentsOf: parent.appendingPathComponent("Photos")) == Data("keep me".utf8))
        }

        @Test func extensionlessArchiveGetsItsOwnFolder() throws {
            let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: parent) }
            let fixture = try #require(Bundle.module.url(forResource: "defaultArchives", withExtension: nil))
                .appendingPathComponent("defaultArchive.zip")
            let archive = parent.appendingPathComponent("Photos")
            try FileManager.default.copyItem(at: fixture, to: archive)
            let detector = ArchiveTypeDetector(catalog: ArchiveTypeCatalog())

            #expect(detector.detect(for: archive) != nil)
            #expect(OneClickExtractionDestination.archiveFolder.directory(for: archive, detector: detector)?.lastPathComponent == "Photos (2)")
        }

        @MainActor @Test(arguments: ZipReader.allCases, [false, true])
        func extractionPreservesExistingOutput(reader: ZipReader, fileBlockedByDirectory: Bool) async throws {
            let fm = FileManager.default
            let destination = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: destination) }

            let marker = Data("keep existing output".utf8)
            let existing = destination.appendingPathComponent("hello world.txt")
            if fileBlockedByDirectory {
                try fm.createDirectory(at: existing, withIntermediateDirectories: true)
                try marker.write(to: existing.appendingPathComponent("keep.txt"))
            } else {
                try marker.write(to: existing)
            }
            try marker.write(to: destination.appendingPathComponent("hello world (2).txt"))
            let danglingLink = destination.appendingPathComponent("hello world (3).txt")
            try fm.createSymbolicLink(atPath: danglingLink.path, withDestinationPath: "missing.txt")
            // An archive directory can also be blocked by an existing file.
            try marker.write(to: destination.appendingPathComponent("folder"))

            let fixture = try #require(Bundle.module.url(forResource: "defaultArchives", withExtension: nil))
                .appendingPathComponent("defaultArchive.zip")
            let content = try #require(Bundle.module.url(forResource: "defaultArchiveContent", withExtension: nil))
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: reader.selector)
            state.progressCenter = ExtractionProgressCenter()
            state.open(url: fixture)
            try await state.openTask?.value
            await withCheckedContinuation { continuation in
                state.onStatusChange = { status in
                    if status == .done { continuation.resume() }
                }
                state.extract(to: destination, smart: false, preservingExistingFiles: true)
            }
            try #require(state.error == nil, "Extraction failed: \(state.error ?? "")")

            #expect(try Data(contentsOf: fileBlockedByDirectory ? existing.appendingPathComponent("keep.txt") : existing) == marker)
            #expect(try Data(contentsOf: destination.appendingPathComponent("hello world (2).txt")) == marker)
            #expect(try fm.destinationOfSymbolicLink(atPath: danglingLink.path) == "missing.txt")
            #expect(try Data(contentsOf: destination.appendingPathComponent("folder")) == marker)
            #expect(try Data(contentsOf: destination.appendingPathComponent("hello world (4).txt")) == Data(contentsOf: content.appendingPathComponent("hello world.txt")))
            #expect(try Data(contentsOf: destination.appendingPathComponent("folder (2)/README.md")) == Data(contentsOf: content.appendingPathComponent("folder/README.md")))
            #expect(try Data(contentsOf: destination.appendingPathComponent("folder (2)/NestedArchive.zip")) == Data(contentsOf: content.appendingPathComponent("folder/NestedArchive.zip")))
            #expect(try fm.contentsOfDirectory(atPath: destination.path).allSatisfy { !$0.hasPrefix(".MacPacker-extract-") })
        }
    }
}
