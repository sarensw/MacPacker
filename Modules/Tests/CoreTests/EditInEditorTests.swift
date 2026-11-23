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

/// Holds every password request until `open`, then answers each with the
/// password; a request after that is answered at once.
private actor PasswordGate {
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    private(set) var asked = 0

    func wait() async -> String? {
        asked += 1
        if !isOpen {
            await withCheckedContinuation { waiting.append($0) }
        }
        return "secret"
    }

    func open() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}

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

        /// notes.txt, encrypted: extracting it asks for the password, which
        /// `PasswordGate` holds until the test lets it through.
        private func makeEncryptedArchive(in dir: URL) throws -> URL {
            let src = dir.appending(component: "src")
            try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
            try "notes\n".write(to: src.appending(component: "notes.txt"), atomically: true, encoding: .utf8)
            let archive = dir.appending(component: "locked.zip")
            try run("/usr/bin/zip", ["-P", "secret", archive.path, "notes.txt"], cwd: src)
            return archive
        }

        /// A second Edit while the first copy is still being extracted brings
        /// no second copy: two editor windows on one entry, one losing out.
        @Test func editingAgainWhileTheCopyIsExtractedHandsOutOne() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let (state, handed) = try await open(try makeEncryptedArchive(in: dir))
            let gate = PasswordGate()
            state.passwordProvider = { _ in await gate.wait() }
            let item = try #require(item("notes.txt", in: state))

            let first = Task { try await state.editAsync(item: item) }
            while await gate.asked == 0 { await Task.yield() }
            let second = Task { try await state.editAsync(item: item) }
            for _ in 0..<50 { await Task.yield() }
            await gate.open()
            try await first.value
            try await second.value

            #expect(handed.urls.count == 1)
        }

        /// The window closed while the copy was being extracted: it is not
        /// handed to the editor, and it does not stay behind.
        @Test func aCopyDoneAfterTheWindowClosedIsDropped() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let (state, handed) = try await open(try makeEncryptedArchive(in: dir))
            let before = Set((try? FileManager.default.contentsOfDirectory(atPath: CacheCleaner.launchFolder.path)) ?? [])
            let gate = PasswordGate()
            state.passwordProvider = { _ in await gate.wait() }
            let item = try #require(item("notes.txt", in: state))

            let edit = Task { try await state.editAsync(item: item) }
            while await gate.asked == 0 { await Task.yield() }
            state.clean()
            await gate.open()
            try? await edit.value
            await state.cleanTask?.value

            #expect(handed.urls.isEmpty)
            let after = Set((try? FileManager.default.contentsOfDirectory(atPath: CacheCleaner.launchFolder.path)) ?? [])
            #expect(after.subtracting(before).isEmpty)
        }

        /// A copy that could not be put back is tried again the next time the
        /// window comes to the front, and the bar names only what is pending.
        @Test func aFailedTakeBackIsTriedAgain() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let (state, handed) = try await open(try makeArchive(.zip, in: dir))
            let copy = try await edit("notes.txt", in: state, handed)
            try saveInEditor("changed\n", into: copy)

            state.scanFiles = { _, _, _ in throw CocoaError(.fileReadNoPermission) }
            #expect(await state.takeBackEdits()?.value == false)
            #expect(state.changedInEditor.isEmpty)
            #expect(!state.hasPendingChanges)

            state.scanFiles = { urls, base, cancel in try await FileScanner().scan(urls, under: base, cancel: cancel) }
            #expect(await state.takeBackEdits()?.value == true)
            #expect(state.changedInEditor == ["notes.txt"])
            #expect(state.hasPendingChanges)
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
