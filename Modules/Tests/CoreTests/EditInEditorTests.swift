//
//  EditInEditorTests.swift
//  Modules
//
//  Edit: an entry is handed to another app as a copy, and what is saved there
//  comes back into the archive as an unsaved edit. The archives are made at
//  test time; none of the checked-in ones is written to.
//

import Testing
import Foundation
@testable import Core

extension AllCoreTests {

    @MainActor struct EditInEditorTests {

        private func makeState() -> ArchiveState {
            ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
        }

        private func item(_ path: String, in state: ArchiveState) -> ArchiveItem? {
            state.entries.values.first { $0.virtualPath == path }
        }

        /// config/settings.ini and notes.txt.
        private func makeArchive(_ kind: EditableArchive, in dir: URL) throws -> URL {
            let src = dir.appending(component: "src")
            try FileManager.default.createDirectory(at: src.appending(component: "config"), withIntermediateDirectories: true)
            try "level = info\n".write(to: src.appending(path: "config/settings.ini"), atomically: true, encoding: .utf8)
            try "notes\n".write(to: src.appending(component: "notes.txt"), atomically: true, encoding: .utf8)
            let archive = dir.appending(component: kind == .zip ? "release.zip" : "release.7z")
            try pack(kind, ["config", "notes.txt"], of: src, into: archive)
            return archive
        }

        /// Opens `archive` in a state whose editor only records what it is handed.
        private func open(_ archive: URL) async throws -> (ArchiveState, Handed) {
            let state = makeState()
            let handed = Handed()
            state.openInEditor = { handed.urls.append($0) }
            state.open(url: archive)
            try await state.openTask?.value
            return (state, handed)
        }

        private final class Handed { var urls: [URL] = [] }

        /// Hands out `path` the way Edit does and returns the copy.
        private func edit(_ path: String, in state: ArchiveState, _ handed: Handed) async throws -> URL {
            try await state.editAsync(item: try #require(item(path, in: state)))
            return try #require(handed.urls.last)
        }

        /// What an editor's save does: other bytes, a later date. Written
        /// atomically, a new file in its place, as CotEditor and TextEdit do.
        private func saveInEditor(_ text: String, into copy: URL) throws {
            try text.write(to: copy, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: copy.path)
        }

        private func content(of path: String, in archive: URL, _ dir: URL) throws -> String {
            let out = dir.appending(component: "out-\(UUID().uuidString)")
            try systemExtract(archive, to: out)
            return try String(contentsOf: out.appending(path: path), encoding: .utf8)
        }

        @Test(arguments: EditableArchive.allCases)
        func aSaveInTheEditorComesBackAsAnUnsavedEdit(in kind: EditableArchive) async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let archive = try makeArchive(kind, in: dir)
            let (state, handed) = try await open(archive)

            let copy = try await edit("config/settings.ini", in: state, handed)
            #expect(try String(contentsOf: copy, encoding: .utf8) == "level = info\n")
            #expect(copy.lastPathComponent == "settings.ini")

            try saveInEditor("level = debug\n", into: copy)
            #expect(await state.takeBackEdits()?.value == true)
            #expect(state.hasPendingChanges)
            #expect(state.changedInEditor == ["settings.ini"])

            await state.save()?.value
            #expect(state.error == nil)
            #expect(state.changedInEditor.isEmpty)
            #expect(try systemEntries(archive).filter { $0.hasSuffix("settings.ini") }.count == 1)
            #expect(try content(of: "config/settings.ini", in: archive, dir) == "level = debug\n")
            #expect(try content(of: "notes.txt", in: archive, dir) == "notes\n")
        }

        /// Coming back without a save in the editor changes nothing.
        @Test func anUntouchedCopyChangesNothing() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let (state, handed) = try await open(try makeArchive(.zip, in: dir))

            _ = try await edit("notes.txt", in: state, handed)

            #expect(state.takeBackEdits() == nil)
            #expect(!state.hasPendingChanges)
            #expect(state.changedInEditor.isEmpty)
        }

        /// The editor keeps the file open after the archive is saved, and what
        /// it saves next comes back too.
        @Test func theCopyOutlivesASave() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let archive = try makeArchive(.zip, in: dir)
            let (state, handed) = try await open(archive)
            let copy = try await edit("notes.txt", in: state, handed)

            try saveInEditor("first\n", into: copy)
            _ = await state.takeBackEdits()?.value
            await state.save()?.value
            await state.cleanTask?.value
            #expect(FileManager.default.fileExists(atPath: copy.path))

            try saveInEditor("second\n", into: copy)
            #expect(await state.takeBackEdits()?.value == true)
            await state.save()?.value
            #expect(try content(of: "notes.txt", in: archive, dir) == "second\n")
        }

        /// Edit on a file already handed out brings that copy forward again.
        @Test func editingTheSameFileTwiceHandsOutOneCopy() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let (state, handed) = try await open(try makeArchive(.zip, in: dir))

            let first = try await edit("notes.txt", in: state, handed)
            let second = try await edit("notes.txt", in: state, handed)

            #expect(first == second)
        }

        /// Closing the window removes the copies with the other temporary files.
        @Test func closingTheWindowRemovesTheCopy() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let (state, handed) = try await open(try makeArchive(.zip, in: dir))
            let copy = try await edit("notes.txt", in: state, handed)

            state.clean()
            await state.cleanTask?.value

            #expect(!FileManager.default.fileExists(atPath: copy.path))
        }

        @Test func foldersCannotBeEdited() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let (state, _) = try await open(try makeArchive(.zip, in: dir))

            #expect(!state.canEdit(try #require(item("config", in: state))))
            #expect(state.canEdit(try #require(item("config/settings.ini", in: state))))
        }

        // MARK: Which editor

        @Test func theChosenEditorIsUsedWhileItIsInstalled() {
            let installed: Set = [TextEditors.cotEditor, TextEditors.textEdit, "com.barebones.bbedit"]

            #expect(TextEditors.resolve(chosen: "com.barebones.bbedit", isInstalled: installed.contains)
                == "com.barebones.bbedit")
        }

        /// No error when the chosen editor was removed: CotEditor, else TextEdit.
        @Test func aMissingEditorFallsBackToCotEditorThenTextEdit() {
            #expect(TextEditors.resolve(chosen: "com.barebones.bbedit",
                                        isInstalled: [TextEditors.cotEditor, TextEditors.textEdit].contains)
                == TextEditors.cotEditor)
            #expect(TextEditors.resolve(chosen: nil, isInstalled: [TextEditors.textEdit].contains)
                == TextEditors.textEdit)
        }

        /// Settings lists only what is installed, plus the Mac's own app for
        /// text and an app picked with "Other…", each once.
        @Test func settingsListsInstalledEditorsOnce() {
            let installed: Set = [TextEditors.textEdit, "com.microsoft.VSCode", "com.sublimetext.4", "org.vim.MacVim"]

            let listed = TextEditors.listed(chosen: "org.vim.MacVim", systemDefault: "com.sublimetext.4",
                                            isInstalled: installed.contains)

            #expect(listed == [TextEditors.textEdit, "com.microsoft.VSCode", "com.sublimetext.4", "org.vim.MacVim"])
        }
    }
}
