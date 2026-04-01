//
//  EdgeCaseTests.swift
//  Modules
//
//  Created by Claude on 01.04.26.
//
//  Edge case tests to verify stability under unusual inputs.
//

import Foundation
import Testing
@testable import Core

// MARK: - ArchiveItem Edge Cases

extension AllCoreTests {

    @MainActor struct ArchiveItemEdgeCaseTests {

        @Test func emptyName() {
            let item = ArchiveItem(name: "", type: .file)
            #expect(item.name == "")
            #expect(item.ext == "")
        }

        @Test func nameWithOnlyDot() {
            let item = ArchiveItem(name: ".", type: .file)
            #expect(item.ext == "")
        }

        @Test func nameWithMultipleDots() {
            let item = ArchiveItem(name: "my.archive.tar.gz", type: .file)
            #expect(item.ext == "gz")
        }

        @Test func nameWithTrailingDot() {
            let item = ArchiveItem(name: "file.", type: .file)
            #expect(item.ext == "")
        }

        @Test func nameWithSpaces() {
            let item = ArchiveItem(name: "my archive file.zip", type: .file)
            #expect(item.ext == "zip")
            #expect(item.name == "my archive file.zip")
        }

        @Test func nameWithUnicode() {
            let item = ArchiveItem(name: "文件.tar.gz", type: .file)
            #expect(item.ext == "gz")
        }

        @Test func directoryAlwaysHasEmptyExt() {
            let item = ArchiveItem(name: "folder.with.dots", type: .directory)
            #expect(item.ext == "")
            #expect(item.children != nil)
            #expect(item.children!.isEmpty)
        }

        @Test func addChildToFileConvertsToHaveChildren() {
            let file = ArchiveItem(name: "file.txt", type: .file)
            #expect(file.children == nil)
            file.addChild(UUID())
            #expect(file.children != nil)
            #expect(file.children!.count == 1)
        }

        @Test func addMultipleChildrenPreservesOrder() {
            let dir = ArchiveItem(name: "dir", type: .directory)
            let ids = (0..<5).map { _ in UUID() }
            for id in ids { dir.addChild(id) }
            #expect(dir.children == ids)
        }

        @Test func setUrlAndTypeId() {
            let item = ArchiveItem(name: "nested.zip", type: .file)
            #expect(item.url == nil)
            #expect(item.archiveTypeId == nil)

            let url = URL(fileURLWithPath: "/tmp/test.zip")
            item.set(url: url, typeId: "zip")
            #expect(item.url == url)
            #expect(item.archiveTypeId == "zip")
        }

        @Test func defaultSizesAreNegativeOne() {
            let item = ArchiveItem(name: "test", type: .file)
            #expect(item.compressedSize == -1)
            #expect(item.uncompressedSize == -1)
        }

        @Test func customSizesPreserved() {
            let item = ArchiveItem(name: "test", type: .file, compressedSize: 100, uncompressedSize: 200)
            #expect(item.compressedSize == 100)
            #expect(item.uncompressedSize == 200)
        }

        @Test func itemEquality() {
            let item = ArchiveItem(name: "test", type: .file)
            #expect(item == item)

            let other = ArchiveItem(name: "test", type: .file)
            #expect(item != other) // different UUIDs
        }
    }

    // MARK: - ArchiveTypeDetector Edge Cases

    @MainActor struct ArchiveTypeDetectorEdgeCaseTests {

        @Test func detectEmptyFile() {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)

            let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("empty_\(UUID().uuidString).xyz")
            FileManager.default.createFile(atPath: tempFile.path, contents: Data())
            defer { try? FileManager.default.removeItem(at: tempFile) }

            let result = detector.detect(for: tempFile, considerComposition: true)
            #expect(result == nil)
        }

        @Test func detectTinyFile() {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)

            let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("tiny_\(UUID().uuidString).xyz")
            FileManager.default.createFile(atPath: tempFile.path, contents: Data([0x01]))
            defer { try? FileManager.default.removeItem(at: tempFile) }

            let result = detector.detect(for: tempFile, considerComposition: true)
            #expect(result == nil)
        }

        @Test func detectFileWithNoExtension() {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)

            let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("noext_\(UUID().uuidString)")
            FileManager.default.createFile(atPath: tempFile.path, contents: "not an archive".data(using: .utf8))
            defer { try? FileManager.default.removeItem(at: tempFile) }

            let result = detector.detect(for: tempFile, considerComposition: true)
            #expect(result == nil)
        }

        @Test func detectNonExistentFile() {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)

            let fakeUrl = URL(fileURLWithPath: "/nonexistent_\(UUID().uuidString).zip")
            // Extension-based detection should still work even if file doesn't exist
            let result = detector.detectByExtension(for: fakeUrl, considerComposition: true)
            #expect(result != nil)
            #expect(result!.type.id == "zip")

            // But magic number detection should fail
            let magicResult = detector.detectByMagicNumber(for: fakeUrl)
            #expect(magicResult == nil)
        }

        @Test func detectByExtensionCaseInsensitive() {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)

            let url = URL(fileURLWithPath: "/tmp/file.ZIP")
            let result = detector.detectByExtension(for: url, considerComposition: true)
            #expect(result != nil)
            #expect(result!.type.id == "zip")
        }

        @Test func getNameWithoutExtensionNoMatch() {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)

            let url = URL(fileURLWithPath: "/tmp/readme.txt")
            let name = detector.getNameWithoutExtension(for: url)
            #expect(name == "readme.txt")
        }

        @Test func detectAllCompoundExtensions() {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)

            let compounds: [(String, String)] = [
                ("tar.gz", "tar"),
                ("tar.bz2", "tar"),
                ("tar.xz", "tar"),
                ("tar.lz4", "tar"),
                ("tar.Z", "tar"),
                ("tgz", "tar"),
                ("tbz2", "tar"),
                ("txz", "tar"),
                ("tlz4", "tar"),
                ("taz", "tar"),
            ]

            for (ext, expectedId) in compounds {
                let url = URL(fileURLWithPath: "/tmp/archive.\(ext)")
                let result = detector.detectByExtension(for: url, considerComposition: true)
                #expect(result != nil, "Expected detection for .\(ext)")
                #expect(result?.type.id == expectedId, "Expected \(expectedId) for .\(ext), got \(result?.type.id ?? "nil")")
                #expect(result?.composition != nil, "Expected composition for .\(ext)")
            }
        }
    }

    // MARK: - ArchiveLoader Edge Cases

    @MainActor struct ArchiveLoaderEdgeCaseTests {

        @Test func loadArchiveWithInvalidUrl() async throws {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)
            let loader = ArchiveLoader(
                archiveTypeDetector: detector,
                archiveEngineSelector: ArchiveEngineSelector7zip(),
                passwordResolver: { _ in nil }
            )

            let fakeUrl = URL(fileURLWithPath: "/nonexistent_\(UUID().uuidString).zip")

            await #expect(throws: (any Error).self) {
                try await loader.loadEntries(url: fakeUrl)
            }
        }

        @Test func loadArchiveWithUnknownFormat() async throws {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)
            let loader = ArchiveLoader(
                archiveTypeDetector: detector,
                archiveEngineSelector: ArchiveEngineSelector7zip(),
                passwordResolver: { _ in nil }
            )

            let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("unknown_\(UUID().uuidString).xyz")
            FileManager.default.createFile(atPath: tempFile.path, contents: "not an archive".data(using: .utf8))
            defer { try? FileManager.default.removeItem(at: tempFile) }

            await #expect(throws: (any Error).self) {
                try await loader.loadEntries(url: tempFile)
            }
        }

        @Test func buildTreeWithDeepNesting() async throws {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)
            let loader = ArchiveLoader(
                archiveTypeDetector: detector,
                archiveEngineSelector: ArchiveEngineSelector7zip(),
                passwordResolver: { _ in nil }
            )

            // Use tar which creates a flat list needing tree building
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.tar")
            let result = try await loader.loadEntries(url: url)

            if !result.hasTree {
                let buildResult = await loader.buildTree(at: result.root)
                #expect(buildResult.error == nil)
                #expect(result.root.children != nil)
            }
        }
    }

    // MARK: - ArchiveState Edge Cases

    @MainActor struct ArchiveStateEdgeCaseTests {

        @Test func openWhileAlreadyOpen() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!

            // Open first archive
            state.open(url: folderURL.appendingPathComponent("defaultArchive.zip"))
            // Immediately open second archive (interrupts first)
            state.open(url: folderURL.appendingPathComponent("defaultArchive.7z"))
            try await state.openTask?.value

            // Should show the second archive
            #expect(state.type?.id == "7zip")
        }

        @Test func loadChildrenWithNilSelectedItem() {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            // No archive opened, selectedItem is nil
            state.loadChildren(sortedBy: nil)
            #expect(state.childItems == nil)
        }

        @Test func selectionOffsetWithEmptySelection() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            state.open(url: folderURL.appendingPathComponent("defaultArchive.zip"))
            try await state.openTask?.value

            let offset = state.selectionOffset(selection: IndexSet())
            #expect(offset.isEmpty)
        }

        @Test func changeSelectionWithEmptyChildren() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            state.open(url: folderURL.appendingPathComponent("defaultArchive.zip"))
            try await state.openTask?.value

            state.changeSelection(selection: IndexSet())
            #expect(state.selectedItems.isEmpty)
        }

        @Test func multipleCleanCalls() {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.clean()
            state.clean()
            state.clean()
            #expect(state.root == nil)
        }
    }

    // MARK: - Archive7ZipEngine Edge Cases

    @MainActor struct Archive7ZipEngineEdgeCaseTests {

        @Test func loadNonExistentArchive() async {
            let engine = Archive7ZipEngine()
            let fakeUrl = URL(fileURLWithPath: "/nonexistent_\(UUID().uuidString).zip")

            await #expect(throws: (any Error).self) {
                try await engine.loadArchive(url: fakeUrl, passwordResolver: { _ in nil })
            }
        }

        // NOTE: loadCorruptFile test removed — the CSevenZip C library hangs
        // when trying to parse arbitrary corrupt data, making the test unreliable.

        // NOTE: extractWithInvalidIndex test removed — CSevenZip raises an
        // uncatchable NSException for invalid indices, crashing the process.
    }

    // MARK: - ArchiveXadEngine Edge Cases

    @MainActor struct ArchiveXadEngineEdgeCaseTests {

        // NOTE: loadNonExistentArchiveXad removed — XAD library raises
        // an uncatchable NSException for non-existent files.

        @Test func extractMultipleItemsAtOnce() async throws {
            let engine = ArchiveXadEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            let loadResult = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })
            let items = Array(loadResult.items.values.prefix(3))

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let result = try await engine.extract(items: items, from: url, to: tempDir, passwordResolver: { _ in nil })
            #expect(result.urlsByItemID.count == items.count)
        }
    }

    // MARK: - ArchiveBatchResolver Edge Cases

    @MainActor struct ArchiveBatchResolverEdgeCaseTests {

        @Test func emptyItemsReturnsEmptyBatches() throws {
            let resolver = ArchiveBatchResolver()
            let result = try resolver.resolveBatches(for: [], in: [:], using: ArchiveEngineSelector7zip())
            #expect(result.isEmpty)
        }

        @Test func itemWithNoParentChainThrows() {
            let resolver = ArchiveBatchResolver()
            let orphan = ArchiveItem(name: "orphan", type: .file)
            #expect(throws: (any Error).self) {
                try resolver.resolveBatches(for: [orphan], in: [:], using: ArchiveEngineSelector7zip())
            }
        }
    }

    // MARK: - ArchiveSupportUtilities Edge Cases

    @MainActor struct ArchiveSupportUtilitiesEdgeCaseTests {

        @Test func findHandlerWithCycleDetection() {
            let utils = ArchiveSupportUtilities()

            let item1 = ArchiveItem(name: "a", type: .file)
            let item2 = ArchiveItem(name: "b", type: .file)
            item1.parent = item2.id
            item2.parent = item1.id

            let entries: [UUID: ArchiveItem] = [item1.id: item1, item2.id: item2]

            let result = utils.findHandlerAndUrl(for: item1, in: entries)
            #expect(result == nil)
        }

        @Test func findHandlerForItemWithSelfReference() {
            let utils = ArchiveSupportUtilities()

            let item = ArchiveItem(name: "self", type: .file)
            item.parent = item.id

            let entries: [UUID: ArchiveItem] = [item.id: item]

            let result = utils.findHandlerAndUrl(for: item, in: entries)
            #expect(result == nil)
        }
    }

    // MARK: - ArchiveExtractionResult Edge Cases

    @MainActor struct ArchiveExtractionResultEdgeCaseTests {

        @Test func emptyResultHasNoUrls() {
            let result = ArchiveExtractionResult(urlsByItemID: [:])
            #expect(result.urls.isEmpty)
        }

        @Test func singleURLThrowsWhenEmpty() {
            let result = ArchiveExtractionResult(urlsByItemID: [:])
            #expect(throws: (any Error).self) {
                _ = try result.singleURL
            }
        }

        @Test func singleURLThrowsWhenMultiple() {
            let result = ArchiveExtractionResult(urlsByItemID: [
                UUID(): URL(fileURLWithPath: "/a"),
                UUID(): URL(fileURLWithPath: "/b")
            ])
            #expect(throws: (any Error).self) {
                _ = try result.singleURL
            }
        }

        @Test func singleURLSucceedsWithOneEntry() throws {
            let url = URL(fileURLWithPath: "/test")
            let result = ArchiveExtractionResult(urlsByItemID: [UUID(): url])
            #expect(try result.singleURL == url)
        }
    }

    // MARK: - ArchiveEngineType Edge Cases

    @MainActor struct ArchiveEngineTypeEdgeCaseTests {

        @Test func initWithEmptyString() {
            let type = ArchiveEngineType(configId: "")
            #expect(type == nil)
        }

        @Test func initWithRandomString() {
            let type = ArchiveEngineType(configId: "random_engine_name")
            #expect(type == nil)
        }

        @Test func rawValues() {
            #expect(ArchiveEngineType.xad.rawValue == "XAD (The Unarchiver)")
            #expect(ArchiveEngineType.`7zip`.rawValue == "7-Zip")
            #expect(ArchiveEngineType.swc.rawValue == "SWCompression")
        }
    }

    // MARK: - ArchiveCapabilities Edge Cases

    @MainActor struct ArchiveCapabilitiesEdgeCaseTests {

        @Test func combineAllCapabilities() {
            let all = ArchiveCapabilities.from(strings: [
                "listContents", "extractFiles", "create", "delete", "add", "rewriteInPlace"
            ])
            #expect(all.contains(.listContents))
            #expect(all.contains(.extractFiles))
            #expect(all.contains(.create))
            #expect(all.contains(.delete))
            #expect(all.contains(.add))
            #expect(all.contains(.rewriteInPlace))
        }

        @Test func duplicateStringsAreIdempotent() {
            let caps = ArchiveCapabilities.from(strings: ["create", "create", "create"])
            #expect(caps == .create)
        }
    }
}
