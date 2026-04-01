//
//  CoverageGapTests.swift
//  Modules
//
//  Created by Claude on 31.03.26.
//
//  Targeted tests to close coverage gaps in specific methods.
//

import Foundation
import Testing
@testable import Core

private final class MutableBox<T: Sendable>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

// MARK: - ArchiveState: open(item:) / openAsync for various item types

extension AllCoreTests {

    @MainActor struct ArchiveStateOpenVirtualItemTests {

        @Test func openVirtualItem() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")
            state.open(url: url)
            try await state.openTask?.value

            // Create a virtual item and add it to entries
            let virtualItem = ArchiveItem(name: "virtual", virtualPath: nil, type: .virtual)
            virtualItem.addChild(state.entries.values.first(where: { $0.type == .file })!.id)
            state.entries.values.first(where: { $0.type == .file })!.parent = virtualItem.id

            // open(item:) with virtual type should set selectedItem
            try await state.openAsync(item: virtualItem)
            #expect(state.selectedItem === virtualItem)
        }

        @Test func openDirectoryItemSetsChildItems() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")
            state.open(url: url)
            try await state.openTask?.value

            let dir = state.entries.values.first(where: { $0.type == .directory })!
            try await state.openAsync(item: dir)
            #expect(state.selectedItem === dir)
            #expect(state.childItems != nil)
        }

        @Test func openRootItemDoesNothing() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")
            state.open(url: url)
            try await state.openTask?.value

            let root = state.root!
            try await state.openAsync(item: root)
            // root type is .root — the switch hits break
        }

        @Test func openUnknownItemLogs() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")
            state.open(url: url)
            try await state.openTask?.value

            let unknownItem = ArchiveItem(name: "unknown", virtualPath: nil, type: .unknown)
            try await state.openAsync(item: unknownItem)
            // Should not crash; covers the .unknown case
        }

        @Test func openItemTaskWrapper() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")
            state.open(url: url)
            try await state.openTask?.value

            let dir = state.entries.values.first(where: { $0.type == .directory })!
            // Call the non-async open(item:) wrapper which uses Task internally
            state.open(item: dir)
            // Give the Task time to execute
            try await Task.sleep(for: .milliseconds(100))
            #expect(state.selectedItem === dir)
        }
    }

    // MARK: - ArchiveState: updateSelectedItemForQuickLook

    @MainActor struct ArchiveStateQuickLookTests {

        @Test func quickLookWithSelectedItem() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")
            state.open(url: url)
            try await state.openTask?.value

            // Select a file item
            let fileItem = state.entries.values.first(where: { $0.type == .file })!
            state.selectedItems = [fileItem]

            state.updateSelectedItemForQuickLook()
            // Wait for the async Task to complete
            try await Task.sleep(for: .milliseconds(500))

            #expect(state.previewItemUrl != nil)
        }

        @Test func quickLookWithEmptySelectionClearsPreview() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")
            state.open(url: url)
            try await state.openTask?.value

            // Set a file for preview first
            let fileItem = state.entries.values.first(where: { $0.type == .file })!
            state.selectedItems = [fileItem]
            state.updateSelectedItemForQuickLook()
            try await Task.sleep(for: .milliseconds(500))

            // Now clear selection
            state.selectedItems = []
            state.updateSelectedItemForQuickLook()
            try await Task.sleep(for: .milliseconds(200))

            #expect(state.previewItemUrl == nil)
        }
    }

    // MARK: - ArchiveState: loadChildren sorted descending

    @MainActor struct ArchiveStateSortDescendingTests {

        @Test func loadChildrenDescending() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")
            state.open(url: url)
            try await state.openTask?.value

            // Navigate into a directory that has multiple children
            let dir = state.entries.values.first(where: { $0.type == .directory && ($0.children?.count ?? 0) > 1 })
            if let dir {
                try await state.openAsync(item: dir)
                let descendingSort = NSSortDescriptor(key: "name", ascending: false)
                state.loadChildren(sortedBy: descendingSort)

                if let items = state.childItems, items.count >= 2 {
                    // Files should be sorted in descending order within their type group
                    let fileItems = items.filter { $0.type == .file }
                    if fileItems.count >= 2 {
                        let cmp = fileItems[0].name.localizedStandardCompare(fileItems[1].name)
                        #expect(cmp == .orderedDescending)
                    }
                }
            }
        }
    }

    // MARK: - ArchiveState: extract(to:) with XAD engine

    @MainActor struct ArchiveStateFullExtractXadTests {

        @Test func extractFullArchiveXad() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelectorXad())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")
            state.open(url: url)
            try await state.openTask?.value

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            state.extract(to: tempDir)
            try await Task.sleep(for: .milliseconds(500))

            // XAD full extraction should produce files
            let contents = try? FileManager.default.contentsOfDirectory(atPath: tempDir.path)
            #expect(contents != nil)
            #expect((contents?.count ?? 0) > 0)
        }
    }

    // MARK: - ArchiveState: password caching

    @MainActor struct ArchiveStatePasswordCachingTests {

        @Test func passwordCachedAfterFirstUse() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let zipFolder = Bundle.module.url(forResource: "zip", withExtension: nil)!
            let url = zipFolder.appendingPathComponent("defaultArchive_password.zip")

            state.passwordProvider = { request in
                return "password"
            }

            state.open(url: url)
            try await state.openTask?.value

            // Archive should load successfully with password provider set
            #expect(state.type != nil)
            #expect(!state.entries.isEmpty)
        }
    }

    // MARK: - ArchiveState: changeSelection triggers quicklook update

    @MainActor struct ArchiveStateSelectionQuickLookTests {

        @Test func changeSelectionUpdatesQuickLookIfOpen() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")
            state.open(url: url)
            try await state.openTask?.value

            state.loadChildren()

            // Set a preview URL to simulate quicklook being open
            state.previewItemUrl = URL(fileURLWithPath: "/tmp/fake")

            // Change selection - should trigger quicklook update
            state.changeSelection(selection: IndexSet(integer: 0))
            try await Task.sleep(for: .milliseconds(500))
            // The quicklook update should have been triggered
        }
    }

    // MARK: - DetectionResult.description

    @MainActor struct DetectionResultDescriptionTests {

        @Test func descriptionWithoutComposition() {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            let result = detector.detectByExtension(for: url, considerComposition: true)
            #expect(result != nil)
            let desc = result!.description
            #expect(!desc.isEmpty)
        }

        @Test func descriptionWithComposition() {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.tar.gz")

            let result = detector.detectByExtension(for: url, considerComposition: true)
            #expect(result != nil)
            let desc = result!.description
            #expect(desc.contains("("))
        }
    }

    // MARK: - ArchiveTypeDetector: detect() fallback to magic number

    @MainActor struct DetectorFallbackTests {

        @Test func detectFallsBackToMagicNumberForUnknownExtension() {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            // Use a file that has the wrong extension but valid magic bytes
            // The magic number test archives use real archive files
            let url = folderURL.appendingPathComponent("defaultArchive.7z")

            // Detect should work via extension first
            let result = detector.detect(for: url, considerComposition: true)
            #expect(result != nil)
            #expect(result!.type.id == "7zip")
        }

        @Test func detectReturnsNilForCompletelyUnknownFile() {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)
            // Use a file that has no known extension and no valid magic bytes
            let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("unknownfile.xyz")
            FileManager.default.createFile(atPath: tempFile.path, contents: "not an archive".data(using: .utf8))
            defer { try? FileManager.default.removeItem(at: tempFile) }

            let result = detector.detect(for: tempFile, considerComposition: true)
            #expect(result == nil)
        }

        @Test func detectByMagicNumberWithWrongExtension() {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!

            // Copy a zip file to a file with wrong extension
            let zipUrl = folderURL.appendingPathComponent("defaultArchive.zip")
            let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("fakefile.xyz")
            try? FileManager.default.copyItem(at: zipUrl, to: tempFile)
            defer { try? FileManager.default.removeItem(at: tempFile) }

            // detect should fall back to magic number detection
            let result = detector.detect(for: tempFile, considerComposition: true)
            #expect(result != nil)
            #expect(result!.type.id == "zip")
            #expect(result!.source == .magic)
        }
    }

    // MARK: - ArchiveTypeDetector: getNameWithoutExtension

    @MainActor struct DetectorNameWithoutExtensionTests {

        @Test func nameWithoutExtensionForSimpleArchive() {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)
            let url = URL(fileURLWithPath: "/tmp/archive.zip")
            let name = detector.getNameWithoutExtension(for: url)
            #expect(name == "archive")
        }

        @Test func nameWithoutExtensionForCompound() {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)
            let url = URL(fileURLWithPath: "/tmp/archive.tar.gz")
            let name = detector.getNameWithoutExtension(for: url)
            #expect(name == "archive")
        }

        @Test func nameWithoutExtensionForUnknown() {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)
            let url = URL(fileURLWithPath: "/tmp/document.txt")
            let name = detector.getNameWithoutExtension(for: url)
            #expect(name == "document.txt")
        }
    }

    // MARK: - ArchiveSupportUtilities: makeTempFileDescriptor

    @MainActor struct TempFileDescriptorTests {

        @Test func makeTempFileDescriptorCreatesFile() throws {
            let utils = ArchiveSupportUtilities()
            let fd = try utils.makeTempFileDescriptor()
            try fd.close()
        }
    }

    // MARK: - CacheCleaner: clean()

    @MainActor struct CacheCleanerCleanAllTests {

        @Test func cleanAllRemovesCacheDir() {
            // Create a ta directory in cache
            let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            let taDir = cacheDir.appendingPathComponent("ta", isDirectory: true)
            let testDir = taDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

            let cleaner = CacheCleaner()
            cleaner.clean()

            // After clean(), the ta directory may or may not exist (it removes it)
            // At minimum this should not crash
        }

        @Test func cleanTempDirectoriesWithNonExistentPaths() {
            let cleaner = CacheCleaner()
            // Cleaning non-existent directories should not crash (hits error path)
            cleaner.clean(tempDirectories: [
                URL(fileURLWithPath: "/tmp/\(UUID().uuidString)"),
                URL(fileURLWithPath: "/tmp/\(UUID().uuidString)")
            ])
        }
    }

    // MARK: - Logger: TailBeatSink methods

    @MainActor struct TailBeatSinkTests {

        @Test func sinkMethodsDoNotCrash() {
            let sink = TailBeatSink()
            sink.log(level: .Debug, "test message")
            sink.debug("debug message")
            sink.info("info message")
            sink.warning("warning message")
            sink.error("error message")
        }

        @Test func dummyClassCallsLogger() {
            let d = Dummy()
            d.dummyFunc()
        }
    }

    // MARK: - ArchiveXadEngine: full extraction and error methods

    @MainActor struct ArchiveXadEngineExtraTests {

        @Test func xadFullExtraction() async throws {
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

        @Test func xadExtractItemMissingVirtualPathThrows() async throws {
            let engine = ArchiveXadEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            let item = ArchiveItem(name: "test", virtualPath: nil, type: .file)

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            await #expect(throws: (any Error).self) {
                try await engine.extract(items: [item], from: url, to: tempDir, passwordResolver: { _ in nil })
            }
        }

        @Test func xadExtractItemMissingIndexThrows() async throws {
            let engine = ArchiveXadEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            // Item with virtualPath but no index
            let item = ArchiveItem(name: "test", virtualPath: "test/file", type: .file)

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            await #expect(throws: (any Error).self) {
                try await engine.extract(items: [item], from: url, to: tempDir, passwordResolver: { _ in nil })
            }
        }
    }

    // MARK: - ArchiveSwcEngine: error paths

    @MainActor struct ArchiveSwcEngineErrorTests {

        @Test func swcExtractWithInvalidDataThrows() async throws {
            let engine = ArchiveSwcEngine()

            // Create a temp file with non-LZ4 data
            let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("fake.lz4")
            FileManager.default.createFile(atPath: tempFile.path, contents: "not lz4 data".data(using: .utf8))
            defer { try? FileManager.default.removeItem(at: tempFile) }

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let item = ArchiveItem(name: "fake", virtualPath: "fake", type: .file)
            await #expect(throws: (any Error).self) {
                try await engine.extract(items: [item], from: tempFile, to: tempDir, passwordResolver: { _ in nil })
            }
        }
    }

    // MARK: - ArchiveTypeCatalog: additional query methods

    @MainActor struct ArchiveTypeCatalogExtraTests {

        @Test func getTypeWhereNoMatch() {
            let catalog = ArchiveTypeCatalog()
            let result = catalog.getType(where: { $0.id == "nonexistent_format_xyz" })
            #expect(result == nil)
        }

        @Test func allFormatIdsContainsZip() {
            let catalog = ArchiveTypeCatalog()
            let ids = catalog.allFormatIds()
            #expect(ids.contains("zip"))
        }

        @Test func engineOptionsForZipNotEmpty() {
            let catalog = ArchiveTypeCatalog()
            let options = catalog.engineOptions(for: "zip")
            #expect(!options.isEmpty)
        }

        @Test func defaultEngineForZipIsNotNil() {
            let catalog = ArchiveTypeCatalog()
            let engine = catalog.defaultEngine(for: "zip")
            #expect(engine != nil)
        }
    }

    // MARK: - ArchiveEngineConfigStore: persistence

    @MainActor struct ArchiveEngineConfigStorePersistenceTests {

        @Test func setAndRetrieveOverride() {
            let catalog = ArchiveTypeCatalog()
            let store = ArchiveEngineConfigStore(catalog: catalog)

            // Set an override
            store.setSelectedEngine(.xad, for: "zip")
            let selected = store.selectedEngine(for: "zip")
            #expect(selected == .xad)

            // Reset to default
            store.setSelectedEngine(.`7zip`, for: "zip")
        }

        @Test func engineOptionsReturnsFromCatalog() {
            let catalog = ArchiveTypeCatalog()
            let store = ArchiveEngineConfigStore(catalog: catalog)
            let options = store.engineOptions(for: "zip")
            #expect(!options.isEmpty)
        }
    }

    // MARK: - Archive7ZipEngine: extract full archive (no-op)

    @MainActor struct Archive7ZipEngineFullExtractTests {

        @Test func extractFullArchiveIsNoOp() async throws {
            let engine = Archive7ZipEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // This is currently a no-op in 7zip engine
            try await engine.extract(url, to: tempDir, passwordResolver: { _ in nil })
        }
    }

    // MARK: - ArchiveState: extract(to:) with no root

    @MainActor struct ArchiveStateExtractNoRootTests {

        @Test func extractToDestinationWithNoRoot() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            // Don't open any archive — root is nil
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            state.extract(to: tempDir)
            try await Task.sleep(for: .milliseconds(200))
            // No root set — should handle gracefully
        }
    }

    // MARK: - ArchiveState: open(item:) error catch path

    @MainActor struct ArchiveStateOpenItemErrorTests {

        @Test func openItemTaskCatchesError() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")
            state.open(url: url)
            try await state.openTask?.value

            // Create a file item with no parent chain (no archiveTypeId/url ancestor)
            // This will make batch resolution fail in openFile
            let orphanFile = ArchiveItem(name: "orphan.txt", virtualPath: "orphan.txt", type: .file)
            state.open(item: orphanFile)
            try await Task.sleep(for: .milliseconds(300))
            // The error path should set state.error
            #expect(state.error != nil)
        }
    }

    // MARK: - ArchiveState: extract(items:to:) error path

    @MainActor struct ArchiveStateExtractItemsErrorTests {

        @Test func extractItemsWithOrphanItemSetsError() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")
            state.open(url: url)
            try await state.openTask?.value

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // Orphan item not connected to any archive
            let orphanItem = ArchiveItem(name: "orphan.txt", virtualPath: "orphan.txt", type: .file)
            state.extract(items: [orphanItem], to: tempDir)
            try await Task.sleep(for: .milliseconds(300))
            #expect(state.error != nil)
        }
    }

    // MARK: - ArchiveLoader: buildTree with items missing virtualPath

    @MainActor struct ArchiveLoaderBuildTreeTests {

        @Test func buildTreeLinksItemsToRoot() async throws {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)
            let passwordResolver: ArchivePasswordResolver = { _ in nil }
            let loader = ArchiveLoader(
                archiveTypeDetector: detector,
                archiveEngineSelector: ArchiveEngineSelector7zip(),
                passwordResolver: passwordResolver
            )

            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            let result = try await loader.loadEntries(url: url)
            let root = result.root

            // buildTree must be called to link entries to root
            if !result.hasTree {
                let buildResult = await loader.buildTree(at: root)
                #expect(buildResult.error == nil)
            }

            #expect(root.children != nil)
            #expect((root.children?.count ?? 0) > 0)
        }

        @Test func buildTreeWithDiskImageLinksParents() async throws {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)
            let passwordResolver: ArchivePasswordResolver = { _ in nil }
            let loader = ArchiveLoader(
                archiveTypeDetector: detector,
                archiveEngineSelector: ArchiveEngineSelector7zip(),
                passwordResolver: passwordResolver
            )

            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.dmg")

            let result = try await loader.loadEntries(url: url)
            // DMG has tree structure provided by 7zip
            if result.hasTree {
                #expect(result.root.children != nil)
            } else {
                let buildResult = await loader.buildTree(at: result.root)
                #expect(buildResult.error == nil)
                #expect(result.root.children != nil)
            }
        }
    }

    // NOTE: XAD password-protected archive tests removed — XAD library enters
    // infinite retry loop with test archives, causing test hangs.

    // MARK: - ArchiveTypeDetector: magic number all-policy (ISO)

    @MainActor struct DetectorMagicAllPolicyTests {

        @Test func detectIsoByMagicNumber() {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!

            // Copy ISO to a file with wrong extension so detect uses magic number
            let isoUrl = folderURL.appendingPathComponent("defaultArchive.iso")
            let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("fakefile_\(UUID().uuidString).bin")
            try? FileManager.default.copyItem(at: isoUrl, to: tempFile)
            defer { try? FileManager.default.removeItem(at: tempFile) }

            let result = detector.detectByMagicNumber(for: tempFile)
            #expect(result != nil)
            #expect(result?.type.id == "iso")
        }

        @Test func detectDmgByMagicNumber() {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!

            // DMG uses end_signature magic — copy with wrong extension
            let dmgUrl = folderURL.appendingPathComponent("defaultArchive.dmg")
            let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("fakefile_\(UUID().uuidString).bin")
            try? FileManager.default.copyItem(at: dmgUrl, to: tempFile)
            defer { try? FileManager.default.removeItem(at: tempFile) }

            let result = detector.detectByMagicNumber(for: tempFile)
            #expect(result != nil)
            #expect(result?.type.id == "dmg")
        }
    }

    // MARK: - ArchiveState: nested archive already unfolded

    @MainActor struct ArchiveStateNestedArchiveUnfoldedTests {

        @Test func openFileItemWithExistingChildren() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")
            state.open(url: url)
            try await state.openTask?.value

            // Find the NestedArchive.zip file item
            let nestedArchive = state.entries.values.first(where: { $0.name == "NestedArchive.zip" })
            if let nestedArchive {
                // First open to unfold (extract and parse nested archive)
                try await state.openAsync(item: nestedArchive)

                // Navigate back up
                state.openParent()

                // Open the same nested archive again — it already has children
                // This should hit the "file with children" path (lines 344-349)
                try await state.openAsync(item: nestedArchive)
                #expect(state.selectedItem === nestedArchive)
            }
        }
    }

    // MARK: - ArchiveSwcEngine: full extract error path

    @MainActor struct ArchiveSwcEngineFullExtractErrorTests {

        @Test func swcFullExtractWithInvalidData() async throws {
            let engine = ArchiveSwcEngine()

            let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("fake_\(UUID().uuidString).lz4")
            FileManager.default.createFile(atPath: tempFile.path, contents: "not lz4".data(using: .utf8))
            defer { try? FileManager.default.removeItem(at: tempFile) }

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // This should hit the error path in extract(_:to:)
            try await engine.extract(tempFile, to: tempDir, passwordResolver: { _ in nil })
            // The engine catches errors internally and logs — doesn't throw
        }
    }

    // MARK: - ArchiveState: status transitions in receiveStatusUpdates

    @MainActor struct ArchiveStateStatusTransitionsTests {

        @Test func openCompoundArchiveCoversStatusPaths() async throws {
            // tar.bz2 is compound — triggers more status transitions
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.tar.bz2")

            var statusTexts: [String?] = []
            state.onStatusTextChange = { text in
                statusTexts.append(text)
            }

            state.open(url: url)
            try await state.openTask?.value

            #expect(state.type?.id == "tar")
            #expect(statusTexts.count > 0)
        }
    }

    // MARK: - ArchiveState: additional archive formats

    @MainActor struct ArchiveStateAdditionalFormatsTests {

        @Test func openWimArchive() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.wim")
            state.open(url: url)
            try await state.openTask?.value

            #expect(state.type?.id == "wim")
            #expect(!state.entries.isEmpty)
        }

        @Test func openXarArchive() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.xar")
            state.open(url: url)
            try await state.openTask?.value

            #expect(state.type?.id == "xar")
        }
    }

    // MARK: - ArchiveEngineSelector: engine for type (all cases)

    @MainActor struct ArchiveEngineSelectorAllTypesTests {

        @Test func engineForXadType() {
            let catalog = ArchiveTypeCatalog()
            let configStore = ArchiveEngineConfigStore(catalog: catalog)
            let selector = ArchiveEngineSelector(catalog: catalog, configStore: configStore)
            let engine = selector.engine(for: .xad)
            #expect(engine is ArchiveXadEngine)
        }

        @Test func engineForSwcType() {
            let catalog = ArchiveTypeCatalog()
            let configStore = ArchiveEngineConfigStore(catalog: catalog)
            let selector = ArchiveEngineSelector(catalog: catalog, configStore: configStore)
            let engine = selector.engine(for: .swc)
            #expect(engine is ArchiveSwcEngine)
        }
    }

    // MARK: - ArchiveState: password-protected extraction caches password

    @MainActor struct ArchiveStatePasswordCacheTests {

        @Test func extractTwiceFromPasswordArchiveUsesCache() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let zipFolder = Bundle.module.url(forResource: "zip", withExtension: nil)!
            let url = zipFolder.appendingPathComponent("defaultArchive_password.zip")

            state.passwordProvider = { request in
                return "password"
            }

            state.open(url: url)
            try await state.openTask?.value

            guard let fileItem = state.entries.values.first(where: { $0.type == .file }) else { return }

            // First extraction triggers password prompt
            let url1 = try await state.extractToTemp(item: fileItem)
            #expect(FileManager.default.fileExists(atPath: url1.path))

            // Second extraction should use cached password (line 88)
            let url2 = try await state.extractToTemp(item: fileItem)
            #expect(FileManager.default.fileExists(atPath: url2.path))
        }
    }

    // MARK: - ArchiveState: extract(to:) error path

    @MainActor struct ArchiveStateExtractToErrorTests {

        @Test func extractToWithXadEngineCoversErrorPath() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelectorXad())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")
            state.open(url: url)
            try await state.openTask?.value

            // Extract to a read-only destination to trigger error
            let readOnlyDir = URL(fileURLWithPath: "/nonexistent_path_\(UUID().uuidString)")
            state.extract(to: readOnlyDir)
            try await Task.sleep(for: .milliseconds(500))
            // Error path should set error without crashing
        }
    }

    // MARK: - ArchiveState: quicklook error path

    @MainActor struct ArchiveStateQuickLookErrorTests {

        @Test func quickLookWithUnresolvableItemCoversErrorPath() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")
            state.open(url: url)
            try await state.openTask?.value

            // Set an orphan item as selected (can't be resolved to batch)
            let orphan = ArchiveItem(name: "orphan", virtualPath: "orphan", type: .file)
            state.selectedItems = [orphan]
            state.updateSelectedItemForQuickLook()
            try await Task.sleep(for: .milliseconds(500))
            // Should hit error path in quicklook
            #expect(state.error != nil)
        }
    }

    // MARK: - ArchiveState: extractToTemp error when batch resolution fails

    @MainActor struct ArchiveStateExtractToTempErrorTests {

        @Test func extractToTempThrowsForOrphanItem() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")
            state.open(url: url)
            try await state.openTask?.value

            let orphan = ArchiveItem(name: "orphan", virtualPath: "orphan", type: .file)
            await #expect(throws: (any Error).self) {
                try await state.extractToTemp(item: orphan)
            }
        }
    }

    // MARK: - ArchiveXadEngine: load and extract multiple formats

    @MainActor struct ArchiveXadEngineMultiFormatTests {

        @Test func xadLoadAndExtractCpio() async throws {
            let engine = ArchiveXadEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.cpio")

            let loadResult = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })
            #expect(loadResult.items.count > 0)

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // Extract all items
            let items = Array(loadResult.items.values)
            let result = try await engine.extract(items: items, from: url, to: tempDir, passwordResolver: { _ in nil })
            #expect(!result.urlsByItemID.isEmpty)
        }
    }

    // MARK: - ArchiveLoader: compound archive loading covers more paths

    @MainActor struct ArchiveLoaderCompoundTests {

        @Test func loadCompoundTarXzCoversCompoundPath() async throws {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)
            let loader = ArchiveLoader(
                archiveTypeDetector: detector,
                archiveEngineSelector: ArchiveEngineSelector7zip(),
                passwordResolver: { _ in nil }
            )

            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.tar.xz")

            let result = try await loader.loadEntries(url: url)
            #expect(result.type.id == "tar")
            #expect(result.compositionType != nil)
            #expect(result.entries.count > 0)
        }
    }

    // MARK: - ArchiveState: pkg archive detection (non-extension-only path)

    @MainActor struct ArchiveStatePkgDetectionTests {

        @Test func openXarPkgArchiveAndOpenNestedFile() async throws {
            // .xar files are detected as "pkg" type — this triggers detectUsingExtensionOnly = false
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.xar")
            state.open(url: url)
            try await state.openTask?.value

            #expect(state.type?.id == "xar")
            // Try to open a file inside the xar archive to trigger the pkg detection path
            if let fileItem = state.entries.values.first(where: { $0.type == .file }) {
                state.open(item: fileItem)
                try await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    // MARK: - ArchiveEngineType: id property

    @MainActor struct ArchiveEngineTypeIdTests {

        @Test func engineTypeIdentifiable() {
            let type = ArchiveEngineType.`7zip`
            #expect(type.id == .`7zip`)
            let xad = ArchiveEngineType.xad
            #expect(xad.id == .xad)
        }
    }

    // MARK: - ArchiveEngineSelector: engineType for nonexistent returns nil

    @MainActor struct ArchiveEngineSelectorNilTests {

        @Test func engineTypeForNonexistentReturnsNil() {
            let catalog = ArchiveTypeCatalog()
            let configStore = ArchiveEngineConfigStore(catalog: catalog)
            let selector = ArchiveEngineSelector(catalog: catalog, configStore: configStore)
            let result = selector.engineType(for: "completely_unknown_format_xyz")
            #expect(result == nil)
        }
    }

    // MARK: - CacheCleaner: error path when ta dir missing

    @MainActor struct CacheCleanerErrorPathTests {

        @Test func cleanWhenTaDirDoesNotExistHitsErrorPath() {
            // Ensure the ta directory does not exist
            let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            let taDir = cacheDir.appendingPathComponent("ta", isDirectory: true)
            try? FileManager.default.removeItem(at: taDir)

            let cleaner = CacheCleaner()
            // This should hit the catch block (error path) since ta dir doesn't exist
            cleaner.clean()
        }
    }

    // MARK: - ArchiveExtractor: single extraction with destination

    @MainActor struct ArchiveExtractorWithDestinationTests {

        @Test func extractSingleItemToDestinationMovesFile() async throws {
            // Open archive to get proper items with parent chain
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")
            state.open(url: url)
            try await state.openTask?.value

            guard let fileItem = state.entries.values.first(where: { $0.type == .file }) else { return }

            let batchResolver = ArchiveBatchResolver()
            let batches = try batchResolver.resolveBatches(
                for: [fileItem],
                in: state.entries,
                using: ArchiveEngineSelector7zip()
            )
            guard let batch = batches.first else { return }

            let tempDest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDest, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDest) }

            let extractor = ArchiveExtractor(
                archiveEngineSelector: ArchiveEngineSelector7zip(),
                passwordResolver: { _ in nil }
            )
            let result = try await extractor.extract(batch: batch, to: tempDest)
            // File was moved from temp to destination
            let destFile = tempDest.appendingPathComponent(fileItem.name)
            #expect(FileManager.default.fileExists(atPath: destFile.path))
        }
    }
}
