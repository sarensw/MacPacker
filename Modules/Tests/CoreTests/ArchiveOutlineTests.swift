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

        // MARK: Drops (#251 G2)

        private func eventually(_ condition: () -> Bool) async throws -> Bool {
            for _ in 0..<500 {
                if condition() { return true }
                try await Task.sleep(for: .milliseconds(10))
            }
            return condition()
        }

        /// A file to drop, and a drag carrying it.
        private func drag(_ name: String, in dir: URL) throws -> (URL, FileDrag) {
            let file = dir.appendingPathComponent(name)
            try Data(name.utf8).write(to: file)
            return (file, FileDrag(file))
        }

        /// Asks the list about a drop on `item` (nil: beside the rows), as
        /// AppKit does while the file is over it.
        @discardableResult
        private func hover(_ list: ArchiveOutlineController, _ drag: FileDrag, over item: ArchiveItem?) -> NSDragOperation {
            list.outlineView(list.outlineView, validateDrop: drag, proposedItem: item, proposedChildIndex: NSOutlineViewDropOnItemIndex)
        }

        private func drop(_ list: ArchiveOutlineController, _ drag: FileDrag, on item: ArchiveItem?) -> Bool {
            hover(list, drag, over: item)
            return list.outlineView(list.outlineView, acceptDrop: drag, item: item, childIndex: NSOutlineViewDropOnItemIndex)
        }

        private func isFaded(_ list: ArchiveOutlineController, _ item: ArchiveItem) throws -> Bool {
            let column = try #require(list.outlineView.tableColumn(withIdentifier: ArchiveViewerColumn.name.identifier))
            let cell = list.outlineView(list.outlineView, viewFor: column, item: item) as? NSTableCellView
            return cell?.textField?.textColor == .tertiaryLabelColor
        }

        /// #251 G2. A file dropped on a folder row goes into that folder; on a
        /// file row, into the folder that file is in; beside the rows, into the
        /// folder shown. The status bar says where, while it is over the row.
        @Test func aDropGoesWhereTheRowSays() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let state = try await openArchive(in: dir)
            let list = makeList(.window, .tree, for: state)
            var hints: [ArchiveDropHint?] = []
            list.onDropHint = { hints.append($0) }
            let docs = try #require(state.childItems?.first { $0.name == "docs" })
            list.outlineView.expandItem(docs)
            let sub = try #require(state.displayedChildren(of: docs).first { $0.name == "sub" })
            let a = try #require(state.displayedChildren(of: docs).first { $0.name == "a.txt" })

            let (_, onFolder) = try drag("onFolder.txt", in: dir)
            #expect(drop(list, onFolder, on: sub))
            #expect(hints.contains(.addInto(["docs", "sub"])), "the status bar did not say where: \(hints)")
            let (_, onFile) = try drag("onFile.txt", in: dir)
            #expect(drop(list, onFile, on: a))
            let (_, beside) = try drag("beside.txt", in: dir)
            #expect(drop(list, beside, on: nil))
            #expect(hints.contains(.addInto([])))

            #expect(try await eventually {
                state.displayedChildren(of: sub).contains { $0.name == "onFolder.txt" } &&
                state.displayedChildren(of: docs).contains { $0.name == "onFile.txt" } &&
                (state.childItems ?? []).contains { $0.name == "beside.txt" }
            }, "dropped elsewhere: \(state.entries.values.map(\.name).sorted())")
            #expect(hints.last == .some(nil), "the status bar still names a target")
        }

        /// #251 G2, G5. A rar inside the zip can't take a file: its row fades
        /// while a file is over the list, refuses the drop, doesn't open on
        /// hover, and the status bar names it. The other rows take the file.
        @Test func aRowThatCantTakeTheFileFadesAndRefusesIt() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let outer = try copyOfFixture("nested", "rarInZip.zip", in: dir)
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.open(url: outer)
            try await state.openTask?.value
            let list = makeList(.window, .tree, for: state)
            var hints: [ArchiveDropHint?] = []
            list.onDropHint = { hints.append($0) }
            let rar = try #require(state.childItems?.first { $0.name == "inner.rar" })
            let readme = try #require(state.childItems?.first { $0.name == "readme.txt" })
            let (_, file) = try drag("dropped.txt", in: dir)
            #expect(try !isFaded(list, rar), "faded with no drag under way")

            #expect(hover(list, file, over: rar) == [])
            #expect(hints.last == .some(.cantChange("inner.rar")))
            #expect(try isFaded(list, rar))
            #expect(try !isFaded(list, readme))
            #expect(!list.outlineView(list.outlineView, shouldExpandItem: rar), "a drag opens an archive nothing goes into")
            #expect(hover(list, file, over: readme) == .copy)
            #expect(!drop(list, file, on: rar), "dropped into the rar")

            #expect(try !isFaded(list, rar), "still faded once the drag is over")
        }

        /// #251 G2. A drop on an archive inside, still closed, unpacks it and
        /// adds the file to its top level.
        @Test func aDropOnAClosedArchiveInsideGoesIntoIt() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let source = dir.appendingPathComponent("source")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try Data("inside".utf8).write(to: source.appendingPathComponent("inside.txt"))
            try run("/usr/bin/zip", ["inner.zip", "inside.txt"], cwd: source)
            let outer = dir.appendingPathComponent("outer.zip")
            try run("/usr/bin/zip", [outer.path, "inner.zip"], cwd: source)
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.open(url: outer)
            try await state.openTask?.value
            let list = makeList(.window, .tree, for: state)
            let inner = try #require(state.childItems?.first { $0.name == "inner.zip" })
            let (_, file) = try drag("dropped.txt", in: dir)

            #expect(drop(list, file, on: inner))

            #expect(try await eventually { state.displayedChildren(of: inner).contains { $0.name == "dropped.txt" } },
                    "not added into the archive inside: \(state.displayedChildren(of: inner).map(\.name))")
        }

        /// The archive of `7z_encrypted_header.7z` inside a zip: its listing
        /// needs the password, `password`.
        private func openLockedInside(in dir: URL) async throws -> (ArchiveState, ArchiveItem) {
            let source = dir.appendingPathComponent("source")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            _ = try copyOfFixture("password", "7z_encrypted_header.7z", in: source)
            let outer = dir.appendingPathComponent("outer.zip")
            try run("/usr/bin/zip", [outer.path, "7z_encrypted_header.7z"], cwd: source)
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.open(url: outer)
            try await state.openTask?.value
            return (state, try #require(state.childItems?.first { $0.name == "7z_encrypted_header.7z" }))
        }

        /// #251 G2. A drag never asks for a password: an archive inside that
        /// needs one stays closed, shows no alert, and the status bar says a
        /// drop asks for it.
        @Test func aDragOpensNoArchiveThatNeedsItsPassword() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let (state, locked) = try await openLockedInside(in: dir)
            let answers = Answers(["password"])
            state.passwordProvider = { _ in await answers.next() }
            let list = makeList(.window, .tree, for: state)
            var hints: [ArchiveDropHint?] = []
            list.onDropHint = { hints.append($0) }

            try await state.openInPlace(item: locked, askingForPassword: false)

            #expect(await answers.asked == 0, "asked for the password during a drag")
            #expect(locked.children == nil, "opened without its password")
            #expect(state.lockedNested.contains(locked.id))
            #expect(state.error == nil, "an alert for the password a drag could not ask for")
            let (_, file) = try drag("dropped.txt", in: dir)
            #expect(hover(list, file, over: locked) == .copy)
            #expect(hints.last == .some(.needsPassword("7z_encrypted_header.7z")))
            #expect(!list.outlineView(list.outlineView, shouldExpandItem: locked), "a drag opens it again")
        }

        /// #251 G2. Dropped on, it asks for the password after the drop, and
        /// the file goes in; Cancel adds nothing.
        @Test func aDropOnALockedArchiveAsksAfterTheDrop() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let (state, locked) = try await openLockedInside(in: dir)
            try await state.openInPlace(item: locked, askingForPassword: false)
            let list = makeList(.window, .tree, for: state)

            let answers = Answers([nil, "password"])
            state.passwordProvider = { _ in await answers.next() }
            let (_, cancelled) = try drag("cancelled.txt", in: dir)
            #expect(drop(list, cancelled, on: locked))
            #expect(try await eventually { !list.loadingItems.contains(locked.id) })
            #expect(await answers.asked == 1, "no password asked for after the drop")
            #expect(locked.children == nil, "opened though the password was cancelled")

            let (_, file) = try drag("dropped.txt", in: dir)
            #expect(drop(list, file, on: locked))
            #expect(try await eventually { state.displayedChildren(of: locked).contains { $0.name == "dropped.txt" } },
                    "not added after the password: \(state.displayedChildren(of: locked).map(\.name))")
            #expect(!state.displayedChildren(of: locked).contains { $0.name == "cancelled.txt" })
            #expect(!state.lockedNested.contains(locked.id))
        }

        /// #251 G2. A drop on a locked archive inside while the drag's own
        /// silent open of it is still running asks for the password all the
        /// same, and the file goes in. Both opens running at once, the drop's
        /// lost its leave to ask: the app test saw no prompt.
        @Test func aDropWhileTheHoverStillOpensTheArchiveAsks() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let (state, locked) = try await openLockedInside(in: dir)
            let answers = Answers(["password"])
            state.passwordProvider = { _ in await answers.next() }
            let list = makeList(.window, .tree, for: state)
            let (_, file) = try drag("dropped.txt", in: dir)

            hover(list, file, over: locked)
            #expect(!list.outlineView(list.outlineView, shouldExpandItem: locked))
            #expect(list.loadingItems.contains(locked.id), "the hover did not start unpacking")
            #expect(list.outlineView(list.outlineView, acceptDrop: file, item: locked, childIndex: NSOutlineViewDropOnItemIndex))

            #expect(try await eventually { state.displayedChildren(of: locked).contains { $0.name == "dropped.txt" } },
                    "not added: \(state.displayedChildren(of: locked).map(\.name))")
            let asked = await answers.asked
            #expect(asked == 1, "asked \(asked) times")
        }

        /// #251 G2. The list is not read anew while a file is dragged over it:
        /// AppKit's drop target goes with a reload, and the drop with it. An
        /// archive inside opened by hovering asked for one, and the app tests'
        /// drops on it never arrived. Once the drag is over, it is read anew.
        @Test func aReloadAskedForDuringADragWaitsForItsEnd() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let state = try await openArchive(in: dir)
            let list = makeList(.window, .tree, for: state)
            let rows = list.outlineView.numberOfRows
            let (_, file) = try drag("dragged.txt", in: dir)
            let added = dir.appendingPathComponent("added.txt")
            try Data("added".utf8).write(to: added)

            hover(list, file, over: nil)
            #expect(await state.add(url: added).value)
            try await Task.sleep(for: .milliseconds(100))

            #expect(list.outlineView.numberOfRows == rows, "the list was read anew under the drag")
            list.outlineView.draggingExited(file)
            #expect(try await eventually { list.outlineView.numberOfRows == rows + 1 }, "not read anew once the drag left")
        }

        /// #251 G2. A drag that moves on before an archive inside is unpacked
        /// stops the unpacking: it stays closed.
        @Test func aLoadADragStartedStopsOnceTheDragMovesOn() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let source = dir.appendingPathComponent("source")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try Data("inside".utf8).write(to: source.appendingPathComponent("inside.txt"))
            try run("/usr/bin/zip", ["inner.zip", "inside.txt"], cwd: source)
            let outer = dir.appendingPathComponent("outer.zip")
            try run("/usr/bin/zip", [outer.path, "inner.zip"], cwd: source)
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.open(url: outer)
            try await state.openTask?.value
            let inner = try #require(state.childItems?.first { $0.name == "inner.zip" })
            let movedOn = ExtractionCancelFlag()
            movedOn.cancel()

            await #expect(throws: (any Error).self) {
                try await state.openInPlace(item: inner, askingForPassword: false, cancel: movedOn)
            }

            #expect(inner.children == nil, "opened after the drag moved on")
        }

        /// #251 G2. After the drop, the rows the drag opened stay open where
        /// the file went in; the others close. A drag that leaves closes all.
        @Test func afterADropOnlyTheRowsGoneIntoStayOpen() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let state = try await openArchive(in: dir)
            let list = makeList(.window, .tree, for: state)
            let docs = try #require(state.childItems?.first { $0.name == "docs" })
            let (_, file) = try drag("dropped.txt", in: dir)

            hover(list, file, over: docs)
            list.outlineView.expandItem(docs)
            let sub = try #require(state.displayedChildren(of: docs).first { $0.name == "sub" })
            list.outlineView.expandItem(sub)
            #expect(drop(list, file, on: docs))

            #expect(list.outlineView.isItemExpanded(docs), "the folder the file went into closed")
            #expect(!list.outlineView.isItemExpanded(sub), "a folder the drag only passed stayed open")

            list.outlineView.collapseItem(docs)
            hover(list, file, over: docs)
            list.outlineView.expandItem(docs)
            list.outlineView.draggingExited(file)
            #expect(!list.outlineView.isItemExpanded(docs), "a drag that left kept a folder open")
        }

        /// #251 G2. A read-only archive leaves a dropped file to the window,
        /// whose one card opens it; an editable one's list takes it.
        @Test func onlyAnEditableArchivesListTakesDrops() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let zip = try await openArchive(in: dir)
            let zipList = makeList(.window, .tree, for: zip)
            let rar = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            rar.open(url: try copyOfFixture("defaultArchives", "defaultArchive.rar", in: dir))
            try await rar.openTask?.value
            let rarList = makeList(.window, .tree, for: rar)
            let preview = makeList(.preview, .tree, for: zip)

            #expect(try await eventually { zipList.outlineView.registeredDraggedTypes.contains(.fileURL) })
            #expect(rarList.outlineView.registeredDraggedTypes.isEmpty)
            #expect(preview.outlineView.registeredDraggedTypes.isEmpty, "Quick Look takes drops")
        }
    }
}

/// What the password prompt answers, one after the other.
private actor Answers {
    private var given: [String?]
    private(set) var asked = 0

    init(_ given: [String?]) { self.given = given }

    func next() -> String? {
        asked += 1
        return given.isEmpty ? nil : given.removeFirst()
    }
}

/// A file dragged over the list, as AppKit hands it to the list's checks.
@MainActor
private final class FileDrag: NSObject, @preconcurrency NSDraggingInfo {
    let draggingPasteboard: NSPasteboard

    init(_ file: URL) {
        draggingPasteboard = NSPasteboard(name: NSPasteboard.Name("ArchiveOutlineTests-\(UUID().uuidString)"))
        draggingPasteboard.clearContents()
        draggingPasteboard.writeObjects([file as NSURL])
    }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions = [],
        for view: NSView?,
        classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}
