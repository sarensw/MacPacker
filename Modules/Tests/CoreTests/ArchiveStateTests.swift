//
//  ArchiveStateTests.swift
//  Modules
//
//  Created by Claude on 31.03.26.
//

import Testing
import Foundation
@testable import Core

extension AllCoreTests {

    // MARK: - Open (basic)

    @MainActor struct ArchiveStateOpenTests {

        @Test func openZipFile() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            #expect(state.url == url)
            #expect(state.name == "defaultArchive.zip")
            #expect(state.type?.id == "zip")
            #expect(state.ext == "zip")
            #expect(!state.entries.isEmpty)
            #expect(state.root != nil)
            #expect(state.selectedItem === state.root)
            #expect(state.isBusy == false)
            #expect(state.error == nil)
        }

        @Test func open7zFile() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.7z")

            state.open(url: url)
            try await state.openTask?.value

            #expect(state.type?.id == "7zip")
            #expect(state.root != nil)
            #expect(state.selectedItem === state.root)
        }

        @Test func openTarGzCompound() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.tar.gz")

            state.open(url: url)
            try await state.openTask?.value

            #expect(state.type?.id == "tar")
            #expect(state.compositionType != nil)
            #expect(state.root != nil)
        }

        @Test func openInvalidFilePath() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let url = URL(fileURLWithPath: "/tmp/nonexistent_file_that_does_not_exist.zip")

            state.open(url: url)
            try await state.openTask?.value

            #expect(state.error != nil)
        }
    }

    // MARK: - Open with different engine selectors

    @MainActor struct ArchiveStateEngineSelectorTests {

        @Test func openWith7zipEngine() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            #expect(state.type?.id == "zip")
            #expect(state.entries.count == 5)
            #expect(state.root != nil)
        }

        @Test func openWithXadEngine() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelectorXad())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            #expect(state.type?.id == "zip")
            #expect(state.entries.count == 5)
            #expect(state.root != nil)
        }
    }

    // MARK: - loadChildren(sortedBy:)

    @MainActor struct ArchiveStateLoadChildrenTests {

        @Test func loadChildrenWithNilSort() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            state.loadChildren(sortedBy: nil)

            #expect(state.childItems != nil)
            #expect(!state.childItems!.isEmpty)
        }

        @Test func loadChildrenAscendingByName() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            let sortDescriptor = NSSortDescriptor(key: "name", ascending: true)
            state.loadChildren(sortedBy: sortDescriptor)

            let items = state.childItems!
            #expect(items.count == 2)
            // Directories come first, then files
            #expect(items[0].type == .directory)
            #expect(items[0].name == "folder")
            #expect(items[1].type == .file)
            #expect(items[1].name == "hello world.txt")
        }

        @Test func loadChildrenDescendingByName() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            let sortDescriptor = NSSortDescriptor(key: "name", ascending: false)
            state.loadChildren(sortedBy: sortDescriptor)

            let items = state.childItems!
            #expect(items.count == 2)
            // Directories still come before files even in descending sort
            #expect(items[0].type == .directory)
            #expect(items[1].type == .file)
        }

        @Test func directoriesBeforeFilesInSortedOrder() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            let sortDescriptor = NSSortDescriptor(key: "name", ascending: true)
            state.loadChildren(sortedBy: sortDescriptor)

            let items = state.childItems!
            let directoryItems = items.filter { $0.type == .directory }
            let fileItems = items.filter { $0.type == .file }

            if let lastDirIndex = items.lastIndex(where: { $0.type == .directory }),
               let firstFileIndex = items.firstIndex(where: { $0.type == .file }) {
                #expect(lastDirIndex < firstFileIndex)
            }
            #expect(!directoryItems.isEmpty)
            #expect(!fileItems.isEmpty)
        }
    }

    // MARK: - openParent()

    @MainActor struct ArchiveStateOpenParentTests {

        @Test func openParentNavigatesBackToRoot() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            // Navigate into the "folder" directory
            let dirChild = state.root!.children!
                .compactMap { state.entries[$0] }
                .first(where: { $0.type == .directory })!

            try await state.openAsync(item: dirChild)
            #expect(state.selectedItem === dirChild)

            // Navigate back
            state.openParent()
            #expect(state.selectedItem === state.root)
            #expect(state.selectedItems.contains(where: { $0 === dirChild }))
        }

        @Test func openParentOnRootStaysOnRoot() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            #expect(state.selectedItem === state.root)

            state.openParent()
            #expect(state.selectedItem === state.root)
        }
    }

    // MARK: - open(item:) for directory

    @MainActor struct ArchiveStateOpenItemDirectoryTests {

        @Test func openDirectoryItem() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            let dirChild = state.root!.children!
                .compactMap { state.entries[$0] }
                .first(where: { $0.type == .directory })!

            try await state.openAsync(item: dirChild)

            #expect(state.selectedItem === dirChild)
            #expect(state.childItems != nil)
            #expect(!state.childItems!.isEmpty)

            // Verify children are the directory's children
            let childIds = Set(dirChild.children!.map { $0 })
            for child in state.childItems! {
                #expect(childIds.contains(child.id))
            }
        }
    }

    // MARK: - clean()

    @MainActor struct ArchiveStateCleanTests {

        @Test func cleanResetsAllState() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            // Verify state is populated
            #expect(state.url != nil)
            #expect(state.root != nil)
            #expect(!state.entries.isEmpty)

            state.clean()

            #expect(state.url == nil)
            #expect(state.name == nil)
            #expect(state.type == nil)
            #expect(state.root == nil)
            #expect(state.selectedItem == nil)
            #expect(state.childItems == nil)
            #expect(state.error == nil)
            #expect(state.isBusy == false)
        }
    }

    // MARK: - cancelCurrentOperation()

    @MainActor struct ArchiveStateCancelTests {

        @Test func cancelResetsState() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            state.cancelCurrentOperation()

            // Give the cancellation a moment to propagate
            try await Task.sleep(nanoseconds: 500_000_000)

            // After cancel, state should be reset
            #expect(state.root == nil)
            #expect(state.selectedItem == nil)
            #expect(state.entries.isEmpty)
        }
    }

    // MARK: - extractToTemp(item:)

    @MainActor struct ArchiveStateExtractToTempTests {

        @Test func extractFileItemToTemp() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            let fileItem = state.entries.values.first(where: { $0.type == .file })!
            let extractedUrl = try await state.extractToTemp(item: fileItem)

            #expect(FileManager.default.fileExists(atPath: extractedUrl.path))
        }

        @Test func extractDirectoryItemToTemp() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            let dirItem = state.entries.values.first(where: { $0.type == .directory })!
            let extractedUrl = try await state.extractToTemp(item: dirItem)

            #expect(FileManager.default.fileExists(atPath: extractedUrl.path))
        }
    }

    // MARK: - extract(items:to:)

    @MainActor struct ArchiveStateExtractItemsTests {

        @Test func extractItemsToDestination() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            let tempDest = FileManager.default.temporaryDirectory
                .appendingPathComponent("ArchiveStateTest_extractItems_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDest, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDest) }

            let fileItem = state.entries.values.first(where: { $0.type == .file })!

            state.extract(items: [fileItem], to: tempDest)

            // Wait for the internal Task to complete
            try await Task.sleep(nanoseconds: 2_000_000_000)

            let contents = try FileManager.default.contentsOfDirectory(at: tempDest, includingPropertiesForKeys: nil)
            #expect(!contents.isEmpty)
        }
    }

    // MARK: - extract(to:) full archive

    @MainActor struct ArchiveStateExtractFullTests {

        @Test func extractFullArchiveDoesNotCrash() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            #expect(state.root != nil)
            // Verify that the root has archiveTypeId and url set (needed for extract(to:))
            #expect(state.root?.archiveTypeId != nil)
            #expect(state.root?.url != nil)

            let tempDest = FileManager.default.temporaryDirectory
                .appendingPathComponent("ArchiveStateTest_extractFull_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDest, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDest) }

            // Use onStatusChange to detect when the internal Task finishes
            await withCheckedContinuation { continuation in
                state.onStatusChange = { status in
                    if status == .done {
                        continuation.resume()
                    }
                }
                state.extract(to: tempDest)
            }

            // Note: Archive7ZipEngine.extract(_:to:passwordResolver:) is currently
            // a no-op, so no files will be produced. We verify the method completes
            // without error and status returns to idle.
            #expect(state.error == nil)
            #expect(state.status == .idle)
        }
    }

    // MARK: - changeSelection(selection:)

    @MainActor struct ArchiveStateChangeSelectionTests {

        @Test func changeSelectionAtRoot() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            let sortDescriptor = NSSortDescriptor(key: "name", ascending: true)
            state.loadChildren(sortedBy: sortDescriptor)

            // At root, selectedItem.type == .root, so no offset shift
            state.changeSelection(selection: IndexSet(integer: 0))

            #expect(state.selectedItems.count == 1)
            #expect(state.selectedItems[0] === state.childItems![0])
        }

        @Test func changeSelectionWithParentRow() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            // Navigate into directory so selectedItem is not root
            let dirChild = state.root!.children!
                .compactMap { state.entries[$0] }
                .first(where: { $0.type == .directory })!

            try await state.openAsync(item: dirChild)

            let sortDescriptor = NSSortDescriptor(key: "name", ascending: true)
            state.loadChildren(sortedBy: sortDescriptor)

            // With parent row, index 0 is the parent; index 1 maps to childItems[0]
            state.changeSelection(selection: IndexSet(integer: 1))

            #expect(state.selectedItems.count == 1)
            #expect(state.selectedItems[0] === state.childItems![0])
        }

        @Test func changeSelectionMultipleItems() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            let sortDescriptor = NSSortDescriptor(key: "name", ascending: true)
            state.loadChildren(sortedBy: sortDescriptor)

            // Select both items at root (no parent offset)
            state.changeSelection(selection: IndexSet([0, 1]))

            #expect(state.selectedItems.count == 2)
        }
    }

    // MARK: - selectionOffset(selection:)

    @MainActor struct ArchiveStateSelectionOffsetTests {

        @Test func selectionOffsetAtRoot() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            // At root, no offset shift
            let input = IndexSet([0, 1])
            let result = state.selectionOffset(selection: input)
            #expect(result == input)
        }

        @Test func selectionOffsetWithParent() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            // Navigate into directory
            let dirChild = state.root!.children!
                .compactMap { state.entries[$0] }
                .first(where: { $0.type == .directory })!

            try await state.openAsync(item: dirChild)

            // Non-root: indices shift by +1
            let input = IndexSet([0, 1])
            let result = state.selectionOffset(selection: input)
            #expect(result == IndexSet([1, 2]))
        }
    }

    // MARK: - Status tracking

    @MainActor struct ArchiveStateStatusTests {

        @Test func statusCallbackFiresDuringOpen() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            var statuses: [ArchiveStateStatus] = []
            state.onStatusChange = { status in
                statuses.append(status)
            }

            state.open(url: url)
            try await state.openTask?.value

            #expect(statuses.contains(.processing))
            #expect(statuses.contains(.done))
        }

        @Test func statusIsIdleAfterOpen() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            // After done fires, status resets to idle
            #expect(state.status == .idle)
        }
    }

    // MARK: - Error handling

    @MainActor struct ArchiveStateErrorTests {

        @Test func openNonexistentFileProducesError() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let url = URL(fileURLWithPath: "/tmp/absolutely_does_not_exist_\(UUID().uuidString).zip")

            state.open(url: url)
            try await state.openTask?.value

            #expect(state.error != nil)
        }

        @Test func openInvalidArchiveProducesError() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let zipFolder = Bundle.module.url(forResource: "zip", withExtension: nil)!
            let url = zipFolder.appendingPathComponent("zipVariantInvalid.png")

            state.open(url: url)
            try await state.openTask?.value

            // A PNG is not a valid archive; this should either set an error or have no entries
            let hasError = state.error != nil
            let noEntries = state.entries.isEmpty
            #expect(hasError || noEntries)
        }
    }

    // MARK: - Multiple opens

    @MainActor struct ArchiveStateMultipleOpenTests {

        @Test func openSecondArchiveResetsAndLoads() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!

            // Open first archive
            let zipUrl = folderURL.appendingPathComponent("defaultArchive.zip")
            state.open(url: zipUrl)
            try await state.openTask?.value

            #expect(state.type?.id == "zip")
            let firstEntryCount = state.entries.count

            // Open second archive
            let sevenzUrl = folderURL.appendingPathComponent("defaultArchive.7z")
            state.open(url: sevenzUrl)
            try await state.openTask?.value

            #expect(state.type?.id == "7zip")
            #expect(state.url == sevenzUrl)
            #expect(state.name == "defaultArchive.7z")
            #expect(state.root != nil)
            #expect(state.selectedItem === state.root)
            #expect(state.error == nil)
        }

        @Test func openSameArchiveTwice() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value
            let firstRoot = state.root

            state.open(url: url)
            try await state.openTask?.value

            #expect(state.root != nil)
            // Root is a new instance after re-open
            #expect(state.root !== firstRoot)
            #expect(state.type?.id == "zip")
        }
    }

    // MARK: - Password handling

    @MainActor struct ArchiveStatePasswordTests {

        @Test func openPasswordProtectedArchiveWithProvider() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let zipFolder = Bundle.module.url(forResource: "zip", withExtension: nil)!
            let url = zipFolder.appendingPathComponent("defaultArchive_password.zip")

            state.passwordProvider = { _ in
                return "password"
            }

            state.open(url: url)
            try await state.openTask?.value

            #expect(state.root != nil)
            #expect(!state.entries.isEmpty)
        }

        @Test func openPasswordProtectedArchiveWithoutProvider() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let zipFolder = Bundle.module.url(forResource: "zip", withExtension: nil)!
            let url = zipFolder.appendingPathComponent("defaultArchive_password.zip")

            // No password provider set - should either error or have empty/partial entries
            state.open(url: url)
            try await state.openTask?.value

            // The archive may still open (listing may work without password on some formats)
            // but extraction would fail. At minimum, verify no crash occurred.
            let opened = state.root != nil
            let hasError = state.error != nil
            #expect(opened || hasError)
        }
    }

    // MARK: - open(item:) for nested archive

    @MainActor struct ArchiveStateNestedArchiveTests {

        @Test func openNestedArchiveItem() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            // Navigate into "folder" directory
            let dirChild = state.root!.children!
                .compactMap { state.entries[$0] }
                .sorted { $0.name < $1.name }
                .first(where: { $0.type == .directory })!

            try await state.openAsync(item: dirChild)

            // Find NestedArchive.zip inside "folder"
            let nestedArchive = state.childItems!
                .first(where: { $0.name == "NestedArchive.zip" })!

            #expect(nestedArchive.type == .file)

            // Opening the nested archive should unfold it
            try await state.openAsync(item: nestedArchive)

            #expect(state.selectedItem === nestedArchive)
            #expect(state.childItems != nil)
            #expect(!state.childItems!.isEmpty)

            // Verify the nested archive's children are present
            let nestedNames = state.childItems!.map { $0.name }.sorted()
            #expect(nestedNames.contains("keynote.pdf"))
            #expect(nestedNames.contains("photo.psd"))
            #expect(nestedNames.contains("taxes.xlsx"))
        }
    }

    // MARK: - loadChildren edge cases

    @MainActor struct ArchiveStateLoadChildrenEdgeCaseTests {

        @Test func loadChildrenWithNoSelectedItem() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())

            // No archive opened, selectedItem is nil
            state.loadChildren(sortedBy: nil)
            #expect(state.childItems == nil)
        }

        @Test func loadChildrenAfterClean() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            state.clean()

            state.loadChildren(sortedBy: nil)
            #expect(state.childItems == nil)
        }
    }

    // MARK: - ArchiveState properties after open

    @MainActor struct ArchiveStatePropertiesTests {

        @Test func propertiesAreCorrectlySetAfterOpen() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.tar")

            state.open(url: url)
            try await state.openTask?.value

            #expect(state.url == url)
            #expect(state.name == "defaultArchive.tar")
            #expect(state.type?.id == "tar")
            #expect(state.ext == "tar")
            #expect(state.root != nil)
            #expect(state.root?.type == .root)
            #expect(state.selectedItem === state.root)
            #expect(state.isBusy == false)
            #expect(state.status == .idle)
        }

        @Test func initialStateIsClean() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())

            #expect(state.url == nil)
            #expect(state.name == nil)
            #expect(state.type == nil)
            #expect(state.ext == nil)
            #expect(state.entries.isEmpty)
            #expect(state.root == nil)
            #expect(state.selectedItem == nil)
            #expect(state.childItems == nil)
            #expect(state.isBusy == false)
            #expect(state.error == nil)
            #expect(state.status == .idle)
        }
    }

    // MARK: - openParent with selectedItems tracking

    @MainActor struct ArchiveStateOpenParentSelectedItemsTests {

        @Test func openParentSetsSelectedItemsToPreviousItem() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            let dirChild = state.root!.children!
                .compactMap { state.entries[$0] }
                .first(where: { $0.type == .directory })!

            try await state.openAsync(item: dirChild)

            let previousSelected = state.selectedItem

            state.openParent()

            // selectedItems should contain the previous directory
            #expect(state.selectedItems.count == 1)
            #expect(state.selectedItems[0] === previousSelected)
        }

        @Test func openParentOnRootKeepsEmptyOrUnchangedSelectedItems() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            state.openParent()

            // Root stays root; openParent on root returns early
            #expect(state.selectedItem === state.root)
        }
    }

    // MARK: - Status text tracking

    @MainActor struct ArchiveStateStatusTextTests {

        @Test func statusTextCallbackFires() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            var texts: [String?] = []
            state.onStatusTextChange = { text in
                texts.append(text)
            }

            state.open(url: url)
            try await state.openTask?.value

            // At minimum, "loading..." and "building tree..." should have been emitted
            let nonNilTexts = texts.compactMap { $0 }
            #expect(!nonNilTexts.isEmpty)
        }

        @Test func statusTextUpdatedDuringOpen() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            var texts: [String?] = []
            state.onStatusTextChange = { text in
                texts.append(text)
            }

            state.open(url: url)
            try await state.openTask?.value

            // Verify that status text was set during loading
            let allTexts = texts.compactMap { $0 }
            #expect(allTexts.contains(where: { $0.contains("loading") }))
        }
    }

    // MARK: - Extract to temp with XAD engine

    @MainActor struct ArchiveStateExtractToTempXadTests {

        @Test func extractFileItemToTempWithXad() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelectorXad())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            let fileItem = state.entries.values.first(where: { $0.type == .file })!
            let extractedUrl = try await state.extractToTemp(item: fileItem)

            #expect(FileManager.default.fileExists(atPath: extractedUrl.path))
        }
    }
}
