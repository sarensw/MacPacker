import CryptoKit
import Foundation
import Testing
@testable import Core

extension AllCoreTests {
    struct DarEngineTests {
        private func fixture(_ name: String) throws -> URL {
            try #require(Bundle.module.url(forResource: "dar", withExtension: nil)).appendingPathComponent(name)
        }
        private func temporary() throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        private func verify(_ destination: URL) throws {
            let expected = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: fixture("expected-files.json")))
            for (path, hash) in expected {
                let data = try Data(contentsOf: destination.appendingPathComponent(path))
                #expect(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == hash)
            }
            var directory: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("nested/empty").path, isDirectory: &directory))
            #expect(directory.boolValue)
        }

        @Test("DAR lists and extracts original fixture bytes", arguments: [
            "plain.1.dar", "gzip.1.dar", "encrypted.1.dar", "split.3.dar", "split-padded.004.dar"
        ])
        func roundTrip(name: String) async throws {
            let engine = ArchiveDarEngine()
            let url = try fixture(name)
            let loaded = try await engine.loadArchive(url: url, passwordResolver: { _ in "macpacker-dar-test" })
            #expect(Set(loaded.items.values.compactMap(\.virtualPath)) == [
                "hello.txt", "payload.bin", "nested", "nested/café.txt", "nested/repeated.txt", "nested/empty"
            ])
            #expect(loaded.isEncrypted == name.hasPrefix("encrypted"))
            let destination = try temporary()
            defer { try? FileManager.default.removeItem(at: destination) }
            try await engine.extract(url, to: destination, passwordResolver: { _ in "macpacker-dar-test" })
            try verify(destination)
        }

        @Test("DAR extracts only the selected file or folder", arguments: ["hello.txt", "nested/café.txt", "nested"])
        func selection(path: String) async throws {
            let engine = ArchiveDarEngine()
            let url = try fixture("gzip.1.dar")
            let loaded = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })
            let item = try #require(loaded.items.values.first { $0.virtualPath == path })
            let destination = try temporary()
            defer { try? FileManager.default.removeItem(at: destination) }
            let extracted = try await engine.extract(item: item, from: url, to: destination, passwordResolver: { _ in nil })
            #expect(extracted == destination.appendingPathComponent(path))
            #expect(FileManager.default.fileExists(atPath: extracted.path))
            #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("payload.bin").path))
            if path != "hello.txt" {
                #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("hello.txt").path))
            }
        }

        @Test("DAR retries a wrong password through the existing resolver")
        func passwordRetry() async throws {
            let result = try await ArchiveDarEngine().loadArchive(url: fixture("encrypted.1.dar")) {
                $0.attempt == 1 ? "wrong" : "macpacker-dar-test"
            }
            #expect(result.items.count == 6)
        }

        @Test("DAR password dismissal cancels opening")
        func passwordCancellation() async throws {
            await #expect(throws: ArchiveError.self) {
                _ = try await ArchiveDarEngine().loadArchive(url: fixture("encrypted.1.dar"), passwordResolver: { _ in nil })
            }
        }

        @Test("Missing DAR slices never install a partial restore", arguments: [1, 2, 4])
        func missingSlice(number: Int) async throws {
            let root = try temporary()
            defer { try? FileManager.default.removeItem(at: root) }
            for slice in 1...4 where slice != number {
                try FileManager.default.copyItem(at: fixture("split.\(slice).dar"), to: root.appendingPathComponent("split.\(slice).dar"))
            }
            let output = root.appendingPathComponent("output")
            await #expect(throws: (any Error).self) {
                try await ArchiveDarEngine().extract(root.appendingPathComponent("split.4.dar"), to: output, passwordResolver: { _ in nil })
            }
            #expect(!FileManager.default.fileExists(atPath: output.path))
        }

        @Test("DAR preserves existing destination content")
        func conflict() async throws {
            let destination = try temporary()
            defer { try? FileManager.default.removeItem(at: destination) }
            let existing = destination.appendingPathComponent("hello.txt")
            try Data("keep me".utf8).write(to: existing)
            await #expect(throws: (any Error).self) {
                try await ArchiveDarEngine().extract(fixture("plain.1.dar"), to: destination, passwordResolver: { _ in nil })
            }
            #expect(try Data(contentsOf: existing) == Data("keep me".utf8))
            #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path) == ["hello.txt"])
        }

        @Test("DAR rejects unsafe relative paths", arguments: ["", "/tmp/file", "../file", "a/../b", "a//b", "a/./b", "a\0b"])
        func unsafePath(path: String) { #expect(!DarEntry.safe(path)) }

        @Test("DAR cancellation does not write destination files")
        func cancellation() async throws {
            let root = try temporary()
            defer { try? FileManager.default.removeItem(at: root) }
            let url = try fixture("plain.1.dar")
            let destination = root.appendingPathComponent("output")
            let operation = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                try await ArchiveDarEngine().extract(url, to: destination, passwordResolver: { _ in nil })
            }
            await #expect(throws: CancellationError.self) { try await operation.value }
            #expect(!FileManager.default.fileExists(atPath: destination.path))
        }

        @Test("DAR accepts an uppercase archive extension")
        func uppercase() async throws {
            let root = try temporary()
            defer { try? FileManager.default.removeItem(at: root) }
            let url = root.appendingPathComponent("plain.1.DAR")
            try FileManager.default.copyItem(at: fixture("plain.1.dar"), to: url)
            let loaded = try await ArchiveDarEngine().loadArchive(url: url, passwordResolver: { _ in nil })
            #expect(loaded.items.count == 6)
        }

        @Test("DAR detection uses the DAR engine and keeps slice naming out of the destination")
        func detection() throws {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)
            let url = try fixture("split-padded.004.dar")
            let detected = try #require(detector.detect(for: url))
            #expect(detected.type.id == "dar")
            #expect(detected.split?.scheme == "dar")
            #expect(catalog.defaultEngine(for: "dar") == .dar)
            #expect(detector.getNameWithoutExtension(for: url) == "split-padded")
            #expect(try DarVolume(url: url).firstURL.lastPathComponent == "split-padded.001.dar")
        }

        @MainActor @Test("DAR opens a padded later slice through the app loader")
        func loader() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelectorDar())
            state.folderAccessProvider = { _ in true }
            state.open(url: try fixture("split-padded.004.dar"))
            try await state.openTask?.value
            #expect(state.error == nil)
            #expect(state.url?.lastPathComponent == "split-padded.001.dar")
            #expect(state.entries.values.contains { $0.name == "hello.txt" })
        }

        @Test("DAR detects corrupt data before installing files")
        func corruptData() async throws {
            let root = try temporary()
            defer { try? FileManager.default.removeItem(at: root) }
            var data = try Data(contentsOf: fixture("plain.1.dar"))
            // Damage payload in the real fixture, leaving its catalogue readable.
            data[4096] ^= 1
            let url = root.appendingPathComponent("damaged.1.dar")
            try data.write(to: url)
            let destination = root.appendingPathComponent("output")
            await #expect(throws: (any Error).self) {
                try await ArchiveDarEngine().extract(url, to: destination, passwordResolver: { _ in nil })
            }
            #expect(!FileManager.default.fileExists(atPath: destination.path))
        }

        @Test("DAR library reports its compiled version")
        func version() { #expect(ArchiveEngineType.dar.libraryVersion == "7.0.5") }
    }
}
