//
//  EngineTests.swift
//  Modules
//
//  Created by Stephan Arenswald on 31.03.26.
//

import Foundation
import Testing
@testable import Core

// MARK: - 1. Archive7ZipEngine Tests

extension AllCoreTests {
    @MainActor struct Archive7ZipEngineTests {

        // MARK: loadArchive

        @Test func loadArchiveZip() async throws {
            let engine = Archive7ZipEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            let result = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })

            #expect(result.items.count > 0)
            #expect(result.hasTree == false)
        }

        @Test func loadArchive7z() async throws {
            let engine = Archive7ZipEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.7z")

            let result = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })

            #expect(result.items.count > 0)
        }

        @Test func loadArchiveIsoReturnsEntries() async throws {
            let engine = Archive7ZipEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.iso")

            let result = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })

            #expect(result.items.count > 0)
        }

        @Test func loadArchiveDmgReturnsEntries() async throws {
            let engine = Archive7ZipEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.dmg")

            let result = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })

            #expect(result.items.count > 0)
        }

        @Test("Disk images report hasTree", arguments: [
            "dmg", "fat", "iso", "qcow2", "vdi", "vhd", "vhdx", "vmdk"
        ])
        func diskImageHasTree(ext: String) async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.\(ext)")

            state.open(url: url)
            try await state.openTask?.value

            // After loading through ArchiveState the tree is built and root has children
            #expect(state.root != nil)
            #expect(state.root!.children != nil)
            #expect(state.root!.children!.count > 0)
        }

        // MARK: extract(items:)

        @Test func extractSingleFileFromZip() async throws {
            let engine = Archive7ZipEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            let loadResult = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })
            let fileItem = loadResult.items.values.first(where: { $0.type == .file })!

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let extractResult = try await engine.extract(
                items: [fileItem],
                from: url,
                to: tempDir,
                passwordResolver: { _ in nil }
            )

            #expect(extractResult.urls.count == 1)
            let extractedURL = try extractResult.singleURL
            #expect(FileManager.default.fileExists(atPath: extractedURL.path))
        }

        @Test func extractMultipleItemsFromZip() async throws {
            let engine = Archive7ZipEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            let loadResult = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })
            let fileItems = Array(loadResult.items.values.filter { $0.type == .file })

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let extractResult = try await engine.extract(
                items: fileItems,
                from: url,
                to: tempDir,
                passwordResolver: { _ in nil }
            )

            #expect(extractResult.urls.count == fileItems.count)
        }

        @Test func extractEmptyItemsThrows() async throws {
            let engine = Archive7ZipEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            await #expect(throws: ArchiveError.self) {
                try await engine.extract(
                    items: [],
                    from: url,
                    to: tempDir,
                    passwordResolver: { _ in nil }
                )
            }
        }

        // MARK: statusStream

        @Test func statusStreamReturnsStream() async throws {
            let engine = Archive7ZipEngine()
            let stream = await engine.statusStream()

            // Verify we can get at least the initial idle status
            var gotStatus = false
            for await status in stream {
                if case .idle = status {
                    gotStatus = true
                }
                break
            }
            #expect(gotStatus)
        }

        // MARK: cancel

        @Test func cancelDoesNotCrash() async throws {
            let engine = Archive7ZipEngine()
            await engine.cancel()
            // If we reach here, cancel did not crash
        }
    }
}

// MARK: - 2. ArchiveXadEngine Tests

extension AllCoreTests {
    @MainActor struct ArchiveXadEngineTests {

        // MARK: loadArchive

        @Test func loadArchiveZipViaXad() async throws {
            let engine = ArchiveXadEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            let result = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })

            #expect(result.items.count > 0)
        }

        @Test func loadArchive7zViaXad() async throws {
            let engine = ArchiveXadEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.7z")

            let result = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })

            #expect(result.items.count > 0)
        }

        @Test func loadArchiveCabViaXad() async throws {
            let engine = ArchiveXadEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.cab")

            let result = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })

            #expect(result.items.count > 0)
        }

        // MARK: extract(items:)

        @Test func extractSingleFileViaXad() async throws {
            let engine = ArchiveXadEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            let loadResult = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })
            let fileItem = loadResult.items.values.first(where: { $0.type == .file })!

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let extractResult = try await engine.extract(
                items: [fileItem],
                from: url,
                to: tempDir,
                passwordResolver: { _ in nil }
            )

            #expect(extractResult.urls.count == 1)
            let extractedURL = try extractResult.singleURL
            #expect(FileManager.default.fileExists(atPath: extractedURL.path))
        }

        @Test func extractDirectoryItemViaXad() async throws {
            let engine = ArchiveXadEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            let loadResult = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })
            let dirItem = loadResult.items.values.first(where: { $0.type == .directory })!

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let extractResult = try await engine.extract(
                items: [dirItem],
                from: url,
                to: tempDir,
                passwordResolver: { _ in nil }
            )

            #expect(extractResult.urls.count == 1)
            let extractedURL = try extractResult.singleURL
            var isDir: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: extractedURL.path, isDirectory: &isDir))
            #expect(isDir.boolValue)
        }

        // MARK: extract(_ url:, to:)

        @Test func fullExtractionViaXad() async throws {
            let engine = ArchiveXadEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            try await engine.extract(url, to: tempDir, passwordResolver: { _ in nil })

            let contents = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
            #expect(contents.count > 0)
        }

        // MARK: statusStream / cancel

        @Test func xadStatusStreamReturnsStream() async throws {
            let engine = ArchiveXadEngine()
            let stream = await engine.statusStream()

            var gotStatus = false
            for await status in stream {
                if case .idle = status {
                    gotStatus = true
                }
                break
            }
            #expect(gotStatus)
        }

        @Test func xadCancelDoesNotCrash() async throws {
            let engine = ArchiveXadEngine()
            await engine.cancel()
        }
    }
}

// MARK: - 3. ArchiveSwcEngine Tests

extension AllCoreTests {
    @MainActor struct ArchiveSwcEngineTests {

        // MARK: loadArchive

        @Test func loadArchiveTarLz4() async throws {
            let engine = ArchiveSwcEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.tar.lz4")

            let result = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })

            // SWC engine reports 1 entry: the inner decompressed file
            #expect(result.items.count == 1)
            let entry = result.items.values.first!
            #expect(entry.name == "defaultArchive.tar")
        }

        @Test func loadArchiveTlz4() async throws {
            let engine = ArchiveSwcEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.tlz4")

            let result = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })

            #expect(result.items.count == 1)
            // "defaultArchive.tlz4" stripped of extension becomes "defaultArchive"
            let entry = result.items.values.first!
            #expect(entry.name == "defaultArchive")
        }

        // MARK: stripFileExtension (indirectly through loadArchive)

        @Test("Strip file extension mapping", arguments: [
            ("tar.lz4", "defaultArchive.tar"),
            ("tlz4", "defaultArchive")
        ])
        func stripFileExtension(arg: (String, String)) async throws {
            let ext = arg.0
            let expectedName = arg.1
            let engine = ArchiveSwcEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.\(ext)")

            let result = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })

            let entry = result.items.values.first!
            #expect(entry.name == expectedName)
        }

        // MARK: extract(items:)

        @Test func extractFromTarLz4() async throws {
            let engine = ArchiveSwcEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.tar.lz4")

            let loadResult = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })
            let item = loadResult.items.values.first!

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let extractResult = try await engine.extract(
                items: [item],
                from: url,
                to: tempDir,
                passwordResolver: { _ in nil }
            )

            #expect(extractResult.urls.count == 1)
            // Verify the decompressed file exists on disk
            let decompressedPath = tempDir.appendingPathComponent("defaultArchive.tar")
            #expect(FileManager.default.fileExists(atPath: decompressedPath.path))
        }

        // MARK: extract(_ url:, to:)

        @Test func fullExtractionSwc() async throws {
            let engine = ArchiveSwcEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.tar.lz4")

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            try await engine.extract(url, to: tempDir, passwordResolver: { _ in nil })

            let decompressedPath = tempDir.appendingPathComponent("defaultArchive.tar")
            #expect(FileManager.default.fileExists(atPath: decompressedPath.path))
        }

        // MARK: statusStream / cancel

        @Test func swcStatusStreamReturnsStream() async throws {
            let engine = ArchiveSwcEngine()
            let stream = await engine.statusStream()

            var gotStatus = false
            for await status in stream {
                if case .idle = status {
                    gotStatus = true
                }
                break
            }
            #expect(gotStatus)
        }

        @Test func swcCancelDoesNotCrash() async throws {
            let engine = ArchiveSwcEngine()
            await engine.cancel()
        }
    }
}

// MARK: - 4. ArchiveExtractor Tests

extension AllCoreTests {
    @MainActor struct ArchiveExtractorTests {

        // MARK: extract(batch:)

        @Test func extractSingleBatch() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            let fileItem = state.entries.values.first(where: { $0.type == .file })!

            let batchResolver = ArchiveBatchResolver()
            let batches = try batchResolver.resolveBatches(
                for: [fileItem],
                in: state.entries,
                using: ArchiveEngineSelector7zip()
            )
            let batch = batches.first!

            let extractor = ArchiveExtractor(
                archiveEngineSelector: ArchiveEngineSelector7zip(),
                passwordResolver: { _ in nil }
            )
            let result = try await extractor.extract(batch: batch)

            #expect(FileManager.default.fileExists(atPath: result.url.path))
            #expect(FileManager.default.fileExists(atPath: result.tempDir.path))
        }

        // MARK: extract(batches:to:)

        @Test func extractBatchesToDestination() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            let fileItems = Array(state.entries.values.filter { $0.type == .file })
            #expect(fileItems.count > 0)

            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: destination) }

            let batchResolver = ArchiveBatchResolver()
            let batches = try batchResolver.resolveBatches(
                for: fileItems,
                in: state.entries,
                using: ArchiveEngineSelector7zip()
            )

            let extractor = ArchiveExtractor(
                archiveEngineSelector: ArchiveEngineSelector7zip(),
                passwordResolver: { _ in nil }
            )
            let result = try await extractor.extract(batches: batches, to: destination)

            #expect(result.urls.count == fileItems.count)
            #expect(result.tempDirs.count > 0)

            // Verify files were moved to destination
            let destContents = try FileManager.default.contentsOfDirectory(atPath: destination.path)
            #expect(destContents.count > 0)
        }

        // MARK: extractAll

        @Test func extractAllToDestination() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: destination) }

            guard let root = state.root,
                  let (archiveTypeId, archiveUrl) = ArchiveSupportUtilities().findHandlerAndUrl(for: root, in: state.entries)
            else {
                throw ArchiveError.extractionFailed("Could not resolve archive info for extractAll")
            }

            let extractor = ArchiveExtractor(
                archiveEngineSelector: ArchiveEngineSelector7zip(),
                passwordResolver: { _ in nil }
            )
            try await extractor.extractAll(archiveUrl, archiveTypeId: archiveTypeId, to: destination)
        }

        // MARK: error cases

        @Test func extractBatchWithNoItemsThrows() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            let emptyBatch = ResolvedBatch(
                archiveURL: url,
                engineType: .`7zip`,
                items: []
            )

            let extractor = ArchiveExtractor(
                archiveEngineSelector: ArchiveEngineSelector7zip(),
                passwordResolver: { _ in nil }
            )

            await #expect(throws: ArchiveError.self) {
                try await extractor.extract(batch: emptyBatch)
            }
        }
    }
}

// MARK: - 5. ArchiveExtractionResult Tests

extension AllCoreTests {
    @MainActor struct ArchiveExtractionResultTests {

        // MARK: singleURL

        @Test func singleURLWithOneEntry() throws {
            let id = UUID()
            let url = URL(fileURLWithPath: "/tmp/test_file.txt")
            let result = ArchiveExtractionResult(urlsByItemID: [id: url])

            let single = try result.singleURL
            #expect(single == url)
        }

        @Test func singleURLWithZeroEntriesThrows() {
            let result = ArchiveExtractionResult(urlsByItemID: [:])

            #expect(throws: ArchiveError.self) {
                try result.singleURL
            }
        }

        @Test func singleURLWithMultipleEntriesThrows() {
            let result = ArchiveExtractionResult(urlsByItemID: [
                UUID(): URL(fileURLWithPath: "/tmp/a.txt"),
                UUID(): URL(fileURLWithPath: "/tmp/b.txt")
            ])

            #expect(throws: ArchiveError.self) {
                try result.singleURL
            }
        }

        // MARK: subscript

        @Test func subscriptByArchiveItem() {
            let item = ArchiveItem(name: "test.txt", type: .file)
            let url = URL(fileURLWithPath: "/tmp/test.txt")
            let result = ArchiveExtractionResult(urlsByItemID: [item.id: url])

            #expect(result[item] == url)
        }

        @Test func subscriptByUUID() {
            let id = UUID()
            let url = URL(fileURLWithPath: "/tmp/test.txt")
            let result = ArchiveExtractionResult(urlsByItemID: [id: url])

            #expect(result[id: id] == url)
        }

        @Test func subscriptByMissingItemReturnsNil() {
            let result = ArchiveExtractionResult(urlsByItemID: [:])
            let item = ArchiveItem(name: "missing.txt", type: .file)

            #expect(result[item] == nil)
        }

        @Test func subscriptByMissingUUIDReturnsNil() {
            let result = ArchiveExtractionResult(urlsByItemID: [:])

            #expect(result[id: UUID()] == nil)
        }
    }
}

// MARK: - 6. Password-Protected Archive Tests

extension AllCoreTests {
    @MainActor struct PasswordProtectedArchiveTests {

        // MARK: 7zip engine with password

        @Test func loadPasswordProtectedZipWith7zip() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let zipFolder = Bundle.module.url(forResource: "zip", withExtension: nil)!
            let url = zipFolder.appendingPathComponent("defaultArchive_password.zip")

            state.passwordProvider = { _ in
                return "password"
            }

            state.open(url: url)
            try await state.openTask?.value

            #expect(state.entries.count > 0)
            #expect(state.root != nil)
        }

        @Test func extractPasswordProtectedFileWith7zip() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let zipFolder = Bundle.module.url(forResource: "zip", withExtension: nil)!
            let url = zipFolder.appendingPathComponent("defaultArchive_password.zip")

            state.passwordProvider = { _ in
                return "password"
            }

            state.open(url: url)
            try await state.openTask?.value

            #expect(state.entries.count > 0)

            let fileItem = state.entries.values.first(where: { $0.type == .file })!
            let extractedURL = try await state.extractToTemp(item: fileItem)
            #expect(FileManager.default.fileExists(atPath: extractedURL.path))
        }

        // MARK: XAD engine with password

        @Test func loadPasswordProtectedZipWithXad() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelectorXad())
            let zipFolder = Bundle.module.url(forResource: "zip", withExtension: nil)!
            let url = zipFolder.appendingPathComponent("defaultArchive_password.zip")

            state.passwordProvider = { _ in
                return "password"
            }

            state.open(url: url)
            try await state.openTask?.value

            #expect(state.entries.count > 0)
            #expect(state.root != nil)
        }

        // MARK: Password cancelled

        @Test func passwordCancelledThrows7zip() async throws {
            let engine = Archive7ZipEngine()
            let zipFolder = Bundle.module.url(forResource: "zip", withExtension: nil)!
            let url = zipFolder.appendingPathComponent("defaultArchive_password.zip")

            // Load archive to get entries (loading does not need password for zip)
            let loadResult = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })
            let fileItem = loadResult.items.values.first(where: { $0.type == .file })!

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // Extraction requires password; returning nil should trigger passwordCancelled
            let passwordResolver: ArchivePasswordResolver = { _ in nil }

            await #expect(throws: ArchiveError.self) {
                try await engine.extract(
                    items: [fileItem],
                    from: url,
                    to: tempDir,
                    passwordResolver: passwordResolver
                )
            }
        }

        @Test func passwordCancelledThrowsXad() async throws {
            let engine = ArchiveXadEngine()
            let zipFolder = Bundle.module.url(forResource: "zip", withExtension: nil)!
            let url = zipFolder.appendingPathComponent("defaultArchive_password.zip")

            let loadResult = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })
            let fileItem = loadResult.items.values.first(where: { $0.type == .file })!

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let passwordResolver: ArchivePasswordResolver = { _ in nil }

            await #expect(throws: ArchiveError.self) {
                try await engine.extract(
                    items: [fileItem],
                    from: url,
                    to: tempDir,
                    passwordResolver: passwordResolver
                )
            }
        }
    }
}
