//
//  ArchiveOutlineTests.swift
//  Modules
//
//  The list the archive window and Quick Look share (#251), driven without a
//  window: what it lists, what a row selects, what each host may do. Keys a
//  user presses and drags go to the app tests.
//

import AppKit
import Testing
import Foundation
@testable import ArchivePreviewUI
@testable import Core

extension AllCoreTests {

    @MainActor struct ArchiveOutlineTests {

        /// docs/ (a.txt, b.txt, sub/c.txt), top.txt and zeta.txt.
        private func openArchive(in dir: URL) async throws -> ArchiveState {
            let source = dir.appendingPathComponent("source")
            for path in ["docs/a.txt", "docs/b.txt", "docs/sub/c.txt", "top.txt", "zeta.txt"] {
                let url = source.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(path.utf8).write(to: url)
            }
            let archive = dir.appendingPathComponent("list.zip")
            try run("/usr/bin/zip", ["-r", archive.path, "."], cwd: source)

            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let defaults = UserDefaults(suiteName: "ArchiveOutlineTests-\(UUID().uuidString)")!
            state.defaults = defaults
            state.listDefaults = defaults
            state.open(url: archive)
            try await state.openTask?.value
            return state
        }

        private func makeList(_ features: ArchiveOutlineFeatures, _ layout: ArchiveOutlineLayout, for state: ArchiveState) -> ArchiveOutlineController {
            let controller = ArchiveOutlineController(features: features, layout: layout)
            _ = controller.view
            controller.state = state
            return controller
        }

        private func names(_ controller: ArchiveOutlineController) -> [String] {
            let outline = controller.outlineView
            return (0..<outline.numberOfRows).compactMap { (outline.item(atRow: $0) as? ArchiveItem)?.name }
        }

        private func enter(_ name: String, in state: ArchiveState) async throws {
            let folder = try #require(state.childItems?.first { $0.name == name })
            try await state.openAsync(item: folder)
        }

        /// #251 B18, B4. The window's Table layout lists one folder, without
        /// triangles or indent, and the `..` row heads it when it is switched
        /// on and there is a folder above.
        @Test func theTableListsOneFolderWithTheParentRowOnTop() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let state = try await openArchive(in: dir)
            let list = makeList(.window, .table, for: state)

            #expect(names(list) == ["docs", "top.txt", "zeta.txt"])
            #expect(list.outlineView.indentationPerLevel == 0)
            let docs = try #require(state.childItems?.first)
            #expect(!list.outlineView.isExpandable(docs), "a folder has a triangle in the Table layout")

            state.defaults.set(true, forKey: Keys.showParentRow)
            try await enter("docs", in: state)
            list.reload()
            #expect(names(list) == ["..", "sub", "a.txt", "b.txt"])
        }

        /// #251 B4. A click on the `..` row selects no entry: there is nothing
        /// in it to extract, preview or delete.
        @Test func theParentRowSelectsNothing() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let state = try await openArchive(in: dir)
            state.defaults.set(true, forKey: Keys.showParentRow)
            try await enter("docs", in: state)
            let list = makeList(.window, .table, for: state)

            list.outlineView.selectRowIndexes(IndexSet([0, 2]), byExtendingSelection: false)

            #expect(state.selectedItems.map(\.name) == ["a.txt"])
        }

        /// #251 B3, #426. ⌘↑ goes up and selects the folder just left. 1.3.0
        /// emptied the selection right after `openParent` had set it.
        @Test func goingUpSelectsTheFolderJustLeft() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let state = try await openArchive(in: dir)
            try await enter("docs", in: state)
            let list = makeList(.window, .table, for: state)

            list.goUp()
            list.reload()

            #expect(state.selectedItems.map(\.name) == ["docs"])
            let row = list.outlineView.selectedRow
            #expect((list.outlineView.item(atRow: row) as? ArchiveItem)?.name == "docs", "the row of the folder left is not selected")
        }

        /// #251 D2, D4, #427. The rows come from what the list showed at its
        /// last reload. A search narrows the state's list at once, the reload
        /// follows a moment later; a row AppKit asks for in between is still
        /// there. 1.3.0 read the live list and crashed now and then.
        @Test func aRowAskedForBeforeTheReloadIsStillThere() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let state = try await openArchive(in: dir)
            let list = makeList(.window, .table, for: state)
            #expect(list.outlineView.numberOfRows == 3)

            state.search("top")   // the state's list is one row long now
            #expect(state.childItems?.count == 1)

            let last = list.outlineView(list.outlineView, child: 2, ofItem: nil) as? ArchiveItem
            #expect(last?.name == "zeta.txt")
            list.reload()
            #expect(names(list) == ["top.txt"])
        }

        /// #251 C2. The selection stays with its entries when the list is
        /// ordered anew around them.
        @Test func theSelectionStaysWithItsEntryWhenTheOrderChanges() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let state = try await openArchive(in: dir)
            let list = makeList(.window, .table, for: state)
            let zeta = try #require(state.childItems?.first { $0.name == "zeta.txt" })
            state.select([zeta])
            list.reload()

            state.listDefaults.set(false, forKey: Keys.defaultOrderColumnAscending)
            state.loadChildren()
            list.reload()

            #expect(names(list) == ["docs", "zeta.txt", "top.txt"])
            #expect((list.outlineView.item(atRow: list.outlineView.selectedRow) as? ArchiveItem) === zeta)
        }

        /// #251 H1. The preview lists the whole archive as a tree from its top,
        /// and may only look: no double click into folders, nothing to drag
        /// out, no key that deletes.
        @Test func thePreviewOnlyLooks() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let state = try await openArchive(in: dir)
            try await enter("docs", in: state)   // a window would now show docs
            let list = makeList(.preview, .tree, for: state)

            #expect(names(list) == ["docs", "top.txt", "zeta.txt"], "the preview does not start at the top")
            let docs = try #require(list.outlineView.item(atRow: 0) as? ArchiveItem)
            #expect(list.outlineView.isExpandable(docs))
            #expect(list.outlineView.doubleAction == nil)
            #expect(list.outlineView(list.outlineView, pasteboardWriterForItem: docs) == nil)
            state.select([docs])
            #expect(!list.canDeleteSelection)
        }
    }
}
