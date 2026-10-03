import Foundation
import Darwin
import Testing
import Swift7zip
@testable import Core

extension AllCoreTests {
    struct MacMetadataOptionsTests {
        @Test @MainActor func metadataPreferenceIsOptIn() throws {
            let defaults = isolatedDefaults()
            let input = CompressionOptions(format: .zip)
            #expect(!ArchiveSaveOptions.applyingFilePreferences(to: input, in: defaults).excludeMacMetadata)
            defaults.set(true, forKey: Keys.excludeMacMetadata)
            #expect(ArchiveSaveOptions.applyingFilePreferences(to: input, in: defaults).excludeMacMetadata)
            defaults.set(false, forKey: Keys.excludeMacMetadata)
            #expect(!ArchiveSaveOptions.applyingFilePreferences(to: input, in: defaults).excludeMacMetadata)
        }

        @Test(arguments: [false, true]) func compressionHonorsMetadataChoice(_ exclude: Bool) async throws {
            let root = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            let input = root.appendingPathComponent("text.txt")
            try Data("contents".utf8).write(to: input)
            setExtendedAttribute("com.apple.metadata:_kMDItemUserTags", Data("tag".utf8), at: input)
            setExtendedAttribute("com.apple.ResourceFork", Data("resource".utf8), at: input)
            #expect(chflags(input.path, UInt32(UF_HIDDEN)) == 0)
            let archive = root.appendingPathComponent("out.zip")
            try SevenZipArchive.writeArchive(source: nil, destination: archive, items: [
                .addFile(archivePath: "text.txt", diskPath: input),
                .addData(archivePath: ".DS_Store", data: Data("finder".utf8)),
                .addData(archivePath: "._ordinary.txt", data: Data("user data".utf8))
            ], options: .init(format: .zip, excludeMacMetadata: exclude))
            let out = root.appendingPathComponent("out")
            try await extractWithOurEngine(archive, to: out)
            #expect(try Data(contentsOf: out.appendingPathComponent("text.txt")) == Data("contents".utf8))
            #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent(".DS_Store").path) == !exclude)
            #expect(extendedAttribute("com.apple.metadata:_kMDItemUserTags", at: out.appendingPathComponent("text.txt")) == (exclude ? nil : Data("tag".utf8)))
            #expect(extendedAttribute("com.apple.ResourceFork", at: out.appendingPathComponent("text.txt")) == (exclude ? nil : Data("resource".utf8)))
            #expect(try out.appendingPathComponent("text.txt").resourceValues(forKeys: [.isHiddenKey]).isHidden == !exclude)
            #expect(try Data(contentsOf: out.appendingPathComponent("._ordinary.txt")) == Data("user data".utf8))
        }

        @Test(arguments: [CompressionOptions.Format.zip, .sevenZ]) func cleanupKeepsExistingArchivesEncrypted(_ format: CompressionOptions.Format) async throws {
            let root = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            let file = root.appendingPathComponent("text.txt")
            try Data("private".utf8).write(to: file)
            setExtendedAttribute("com.apple.metadata:_kMDItemUserTags", Data("tag".utf8), at: file)
            let archive = root.appendingPathComponent("locked." + format.rawValue)
            try SevenZipArchive.writeArchive(source: nil, destination: archive, items: [.addFile(archivePath: "text.txt", diskPath: file)], options: .init(format: format, password: "secret", encryptFileNames: format == .sevenZ))
            try SevenZipArchive.writeArchive(source: archive, destination: archive, items: [], options: .init(format: format, excludeMacMetadata: true), sourcePassword: "secret")
            let opened = try SevenZipArchive(url: archive, password: "secret")
            #expect(try opened.entries.allSatisfy(\.isEncrypted))
            if format == .sevenZ { #expect(throws: (any Error).self) { try SevenZipArchive(url: archive) } }
            let out = root.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            try opened.extractAll(to: out)
            #expect(try Data(contentsOf: out.appendingPathComponent("text.txt")) == Data("private".utf8))
            #expect(extendedAttribute("com.apple.metadata:_kMDItemUserTags", at: out.appendingPathComponent("text.txt")) == nil)
        }

        @Test(arguments: [false, true]) func customFolderIconsFollowTheOption(_ exclude: Bool) async throws {
            let root = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            let folder = root.appendingPathComponent("CustomFolder")
            try makeFolderWithCustomIcon(at: folder, fork: Data("icon".utf8))
            let archive = root.appendingPathComponent("folder.zip")
            try SevenZipArchive.writeArchive(source: nil, destination: archive, items: [
                .addDirectory(archivePath: "CustomFolder", diskPath: folder),
                .addFile(archivePath: "CustomFolder/" + customIconFileName, diskPath: folder.appendingPathComponent(customIconFileName))
            ], options: .init(format: .zip, excludeMacMetadata: exclude))
            let out = root.appendingPathComponent("out")
            try await extractWithOurEngine(archive, to: out)
            #expect(finderFlags(at: out.appendingPathComponent("CustomFolder")) == (exclude ? nil : FinderFlag.hasCustomIcon))
            #expect(extendedAttribute("com.apple.ResourceFork", at: out.appendingPathComponent("CustomFolder/" + customIconFileName)) == (exclude ? nil : Data("icon".utf8)))
        }

        @Test(arguments: [false, true]) func existingMetadataIsRemovedWhenRequested(_ saveAs: Bool) async throws {
            let root = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            let input = root.appendingPathComponent("text.txt")
            try Data("contents".utf8).write(to: input)
            setExtendedAttribute("com.apple.metadata:_kMDItemUserTags", Data("tag".utf8), at: input)
            let source = root.appendingPathComponent("source.zip")
            try SevenZipArchive.writeArchive(source: nil, destination: source, items: [
                .addFile(archivePath: "text.txt", diskPath: input),
                .addData(archivePath: ".DS_Store", data: Data("finder".utf8)),
                .addData(archivePath: "notes", data: Data("notes".utf8)),
                .addData(archivePath: "._notes", data: Data("ordinary".utf8))
            ], options: .init(format: .zip))
            let target = saveAs ? root.appendingPathComponent("copy.zip") : source
            try SevenZipArchive.writeArchive(source: source, destination: target, items: [], options: .init(format: .zip, excludeMacMetadata: true))
            let out = root.appendingPathComponent("out")
            try await extractWithOurEngine(target, to: out)
            #expect(extendedAttribute("com.apple.metadata:_kMDItemUserTags", at: out.appendingPathComponent("text.txt")) == nil)
            #expect(!FileManager.default.fileExists(atPath: out.appendingPathComponent(".DS_Store").path))
            #expect(try Data(contentsOf: out.appendingPathComponent("._notes")) == Data("ordinary".utf8))
        }
    }
}
