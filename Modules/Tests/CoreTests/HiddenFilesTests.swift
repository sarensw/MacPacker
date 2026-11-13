//
//  HiddenFilesTests.swift
//  Modules
//
//  Files Finder hides stay out of the listing unless the user shows them, and
//  are greyed out when shown (#304).
//

import AppKit
import Foundation
import Testing
@testable import ArchivePreviewUI
@testable import Core

extension AllCoreTests {
    @MainActor struct HiddenFilesTests {

        /// Opens a fixture from `TestArchives/zip` with hidden files hidden or
        /// shown, whatever this machine's setting is.
        private func open(_ name: String, showsHiddenFiles: Bool = false) async throws -> ArchiveState {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.showsHiddenFiles = showsHiddenFiles
            let folder = try #require(Bundle.module.url(forResource: "zip", withExtension: nil))
            state.open(url: folder.appendingPathComponent(name))
            try await state.openTask?.value
            return state
        }

        private func names(_ items: [ArchiveItem]?) -> [String] {
            (items ?? []).map(\.name).sorted()
        }

        /// Unset means hidden, in the app and in the Quick Look extension alike.
        @Test func hiddenFilesStayHiddenWhenUnset() {
            let defaults = isolatedDefaults()

            #expect(!Keys.showHiddenFilesEnabled(in: defaults))

            defaults.set(true, forKey: Keys.showHiddenFiles)
            #expect(Keys.showHiddenFilesEnabled(in: defaults))
        }

        @Test func hiddenFilesAreLeftOut() async throws {
            let state = try await open("hiddenFiles.zip")
            #expect(names(state.childItems) == ["folder", "readme.txt"])

            let folder = try #require(state.childItems?.first { $0.name == "folder" })
            try await state.openAsync(item: folder)
            #expect(names(state.childItems) == ["notes.txt"])
        }

        @Test func hiddenFilesAreListedWhenShown() async throws {
            let state = try await open("hiddenFiles.zip", showsHiddenFiles: true)
            #expect(names(state.childItems) == [".DS_Store", ".git", "folder", "readme.txt"])

            let folder = try #require(state.childItems?.first { $0.name == "folder" })
            try await state.openAsync(item: folder)
            #expect(names(state.childItems) == [".DS_Store", "notes.txt"])
        }

        /// The setting changes while the window is open: the list follows, and
        /// a selection the list may no longer show goes.
        @Test func switchingRelistsAndClearsTheSelection() async throws {
            let state = try await open("hiddenFiles.zip", showsHiddenFiles: true)
            let dsStore = try #require(state.childItems?.first { $0.name == ".DS_Store" })
            state.selectedItems = [dsStore]
            state.isReloadNeeded = false

            state.showsHiddenFiles = false
            #expect(names(state.childItems) == ["folder", "readme.txt"])
            #expect(state.selectedItems.isEmpty)
            #expect(state.isReloadNeeded)

            state.showsHiddenFiles = true
            #expect(names(state.childItems) == [".DS_Store", ".git", "folder", "readme.txt"])
        }

        /// `.git/HEAD` is not hidden by its own name, only by the folder it is in.
        @Test func searchLeavesOutWhatIsInsideAHiddenFolder() async throws {
            let state = try await open("hiddenFiles.zip")
            state.search("HEAD")
            #expect(names(state.childItems).isEmpty)
            state.search("DS_Store")
            #expect(names(state.childItems).isEmpty)

            state.showsHiddenFiles = true
            #expect(names(state.childItems) == [".DS_Store", ".DS_Store"])
            state.search("HEAD")
            #expect(names(state.childItems) == ["HEAD"])
        }

        /// `Icon\r` holds a folder's custom icon and is invisible in Finder,
        /// dot or not.
        @Test func customIconFileIsHidden() async throws {
            let state = try await open("customicon.zip")
            let folder = try #require(state.childItems?.first { $0.name == "CustomFolder" })
            try await state.openAsync(item: folder)
            #expect(names(state.childItems) == ["note.txt"])

            state.showsHiddenFiles = true
            #expect(names(state.childItems) == ["Icon\r", "note.txt"])
        }

        /// Everything the list shows is selected: that is the whole archive to
        /// the user, so the smart folder rule applies as for "Extract archive".
        @Test func selectingEverythingListedExtractsLikeTheWholeArchive() async throws {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }

            let state = try await open("hiddenFiles.zip")
            let listed = try #require(state.childItems)
            await withCheckedContinuation { continuation in
                state.onStatusChange = { status in
                    if status == .done { continuation.resume() }
                }
                state.extract(items: listed, to: dir, smart: true)
            }

            #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["hiddenFiles"])
        }

        // MARK: - Quick Look

        private func outline(of controller: ArchiveViewController) throws -> NSOutlineView {
            let scrollView = try #require(controller.view.subviews.first as? NSScrollView)
            return try #require(scrollView.documentView as? NSOutlineView)
        }

        private func rows(_ outline: NSOutlineView) -> [String] {
            (0..<outline.numberOfRows).compactMap { (outline.item(atRow: $0) as? ArchiveItem)?.name }.sorted()
        }

        @Test func quickLookLeavesHiddenFilesOut() async throws {
            let state = try await open("hiddenFiles.zip")
            let controller = ArchiveViewController()
            let outline = try outline(of: controller)
            controller.state = state

            #expect(rows(outline) == ["folder", "readme.txt"])
            let folder = try #require(state.entries.values.first { $0.name == "folder" })
            outline.expandItem(folder)
            #expect(rows(outline) == ["folder", "notes.txt", "readme.txt"])
        }

        @Test func quickLookGreysOutHiddenFilesWhenShown() async throws {
            let state = try await open("hiddenFiles.zip", showsHiddenFiles: true)
            let controller = ArchiveViewController()
            let outline = try outline(of: controller)
            controller.state = state
            #expect(rows(outline) == [".DS_Store", ".git", "folder", "readme.txt"])

            for row in 0..<outline.numberOfRows {
                let item = try #require(outline.item(atRow: row) as? ArchiveItem)
                for column in outline.tableColumns {
                    let cell = try #require(outline.delegate?.outlineView?(outline, viewFor: column, item: item))
                    #expect(cell.alphaValue == (item.name.hasPrefix(".") ? 0.5 : 1), "\(item.name), \(column.identifier.rawValue)")
                }
            }
        }
    }
}
