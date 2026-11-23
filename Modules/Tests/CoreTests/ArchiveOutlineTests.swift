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

        /// #251 B14, B4. In the window's Tree layout a folder opens in place on
        /// its triangle: its rows follow it, one level in, and the window stays
        /// in the folder it shows. The `..` row is the table's alone, whatever
        /// the setting says.
        @Test func aFolderOpensInPlaceInTheTree() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let state = try await openArchive(in: dir)
            state.defaults.set(true, forKey: Keys.showParentRow)
            let list = makeList(.window, .tree, for: state)
            let docs = try #require(state.childItems?.first { $0.name == "docs" })
            #expect(list.outlineView.isExpandable(docs))

            list.outlineView.expandItem(docs)

            #expect(names(list) == ["docs", "sub", "a.txt", "b.txt", "top.txt", "zeta.txt"])
            #expect(list.outlineView.level(forItem: try #require(state.entries.values.first { $0.name == "a.txt" })) == 1)
            #expect(state.selectedItem === state.root, "the window left the folder it shows")
        }

        /// #251 B15. An archive inside opens in place on its triangle: what it
        /// holds hangs below its row, and the window keeps its folder, its title
        /// and its selection. Before, opening one took the window into it.
        @Test func anArchiveInsideOpensInPlace() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let source = dir.appendingPathComponent("source")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try Data("inside".utf8).write(to: source.appendingPathComponent("inside.txt"))
            try Data("top".utf8).write(to: source.appendingPathComponent("top.txt"))
            try run("/usr/bin/zip", ["inner.zip", "inside.txt"], cwd: source)
            let outer = dir.appendingPathComponent("outer.zip")
            try run("/usr/bin/zip", [outer.path, "inner.zip", "top.txt"], cwd: source)

            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.open(url: outer)
            try await state.openTask?.value
            let top = try #require(state.childItems?.first { $0.name == "top.txt" })
            state.select([top])
            let inner = try #require(state.childItems?.first { $0.name == "inner.zip" })

            try await state.openInPlace(item: inner)

            #expect(state.displayedChildren(of: inner).map(\.name) == ["inside.txt"])
            #expect(state.selectedItem === state.root, "the window went into the archive")
            #expect(state.name == "outer.zip", "the title follows the archive inside")
            #expect(state.selectedItems.map(\.name) == ["top.txt"], "the selection is gone")
        }

        /// #251 D2. A search lists flat results; cleared, the tree is back with
        /// the folders that were open.
        @Test func clearingASearchOpensTheFoldersAgain() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let state = try await openArchive(in: dir)
            let list = makeList(.window, .tree, for: state)
            let docs = try #require(state.childItems?.first { $0.name == "docs" })
            list.outlineView.expandItem(docs)

            state.search("txt")
            list.reload()
            #expect(!list.outlineView.isExpandable(docs), "a search result has a triangle")
            state.search("")
            list.reload()

            #expect(list.outlineView.isItemExpanded(docs), "the folder opened before the search is closed")
            #expect(names(list) == ["docs", "sub", "a.txt", "b.txt", "top.txt", "zeta.txt"])
        }

        /// #251 C4, F2. In a tree a folder can be selected together with rows
        /// inside it. Extracted, what the folder holds comes once, in the
        /// folder, not a second time on its own. (It held before the tree:
        /// a guard against a change of the extraction.)
        @Test func aFolderSelectedWithRowsInsideItIsExtractedOnce() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let state = try await openArchive(in: dir)
            let docs = try #require(state.childItems?.first { $0.name == "docs" })
            let a = try #require(state.entries.values.first { $0.name == "a.txt" })
            let dest = dir.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

            await withCheckedContinuation { continuation in
                state.onStatusChange = { status in
                    if status == .done { continuation.resume() }
                }
                state.extract(items: [docs, a], to: dest, smart: false)
            }

            let contents = try FileManager.default.contentsOfDirectory(atPath: dest.path).sorted()
            #expect(contents == ["docs"], "a file of the folder came a second time: \(contents)")
            let inDocs = try FileManager.default.contentsOfDirectory(atPath: dest.appendingPathComponent("docs").path).sorted()
            #expect(inDocs == ["a.txt", "b.txt", "sub"], "a file of the folder came a second time: \(inDocs)")
        }

        /// #251 C4, F5. Dragged out together with its folder, a row inside it
        /// comes with the folder, not a second time on its own: each dragged row
        /// is a file of its own that Finder asks for.
        @Test func aRowInsideAFolderDraggedAlongComesWithTheFolder() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let state = try await openArchive(in: dir)
            let list = makeList(.window, .tree, for: state)
            let docs = try #require(state.childItems?.first { $0.name == "docs" })
            let a = try #require(state.entries.values.first { $0.name == "a.txt" })
            let top = try #require(state.childItems?.first { $0.name == "top.txt" })

            state.select([docs, a, top])

            #expect(list.outlineView(list.outlineView, pasteboardWriterForItem: docs) != nil)
            #expect(list.outlineView(list.outlineView, pasteboardWriterForItem: top) != nil)
            #expect(list.outlineView(list.outlineView, pasteboardWriterForItem: a) == nil, "the file comes a second time, beside its folder")
        }

        /// Adds a file, so there is something to save, and saves.
        private func addAndSave(_ state: ArchiveState, in dir: URL) async throws {
            let added = dir.appendingPathComponent("added.txt")
            try Data("added".utf8).write(to: added)
            #expect(await state.add(url: added).value)
            let save = try #require(state.save())
            await save.value
            #expect(state.error == nil)
        }

        /// #251 G7, C2. A save reads the archive anew, every entry a new
        /// object; the window stays in the folder it shows, and the selection
        /// stays with its entries. 1.3.0 went back to the top level.
        @Test func aSaveKeepsTheFolderShownAndTheSelection() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let state = try await openArchive(in: dir)
            try await enter("docs", in: state)
            let a = try #require(state.childItems?.first { $0.name == "a.txt" })
            state.select([a])

            try await addAndSave(state, in: dir)

            #expect(state.selectedItem?.name == "docs", "the window went back to the top level")
            #expect(state.selectedItems.map(\.name) == ["a.txt"])
            #expect(state.selectedItems.first !== a, "the entry was not read anew")
        }

        /// #251 G7. The folders open in the tree when a save began are open
        /// again once it has read the archive anew.
        @Test func aSaveKeepsTheFoldersOpen() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let state = try await openArchive(in: dir)
            let list = makeList(.window, .tree, for: state)
            let docs = try #require(state.childItems?.first { $0.name == "docs" })
            list.outlineView.expandItem(docs)
            let sub = try #require(state.entries.values.first { $0.name == "sub" })
            list.outlineView.expandItem(sub)

            try await addAndSave(state, in: dir)
            list.reload()

            let names = names(list)
            #expect(names.prefix(5) == ["docs", "sub", "c.txt", "a.txt", "b.txt"], "\(names)")
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
