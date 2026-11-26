//
//  ListSettingsTests.swift
//  Modules
//
//  The list the archive window and the Quick Look preview share (#251): one
//  sort order at every level, one formatter, the settings in the app group.
//

import Testing
import Foundation
@testable import Core

extension AllCoreTests {

    @MainActor struct ListSettingsTests {

        /// A store of its own for each test, so none sees another's sort.
        private func makeDefaults() -> UserDefaults {
            let name = "ListSettingsTests-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defaults.removePersistentDomain(forName: name)
            return defaults
        }

        /// zeta.txt (3 bytes), empty.txt (0 bytes), Beta/one.txt, and alpha/
        /// holding b.txt (20 bytes), A.txt (5 bytes) and sub/c.txt.
        private func openArchive(in dir: URL, listSortedBy defaults: UserDefaults) async throws -> ArchiveState {
            let source = dir.appendingPathComponent("source")
            let files: [(String, Int)] = [
                ("zeta.txt", 3), ("empty.txt", 0), ("Beta/one.txt", 1),
                ("alpha/b.txt", 20), ("alpha/A.txt", 5), ("alpha/sub/c.txt", 1),
            ]
            for (path, size) in files {
                let url = source.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(repeating: 0x78, count: size).write(to: url)
            }
            let archive = dir.appendingPathComponent("list.zip")
            try run("/usr/bin/zip", ["-r", archive.path, "."], cwd: source)

            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.listDefaults = defaults
            state.open(url: archive)
            try await state.openTask?.value
            return state
        }

        private func names(_ items: [ArchiveItem]) -> [String] { items.map(\.name) }

        /// #251 H6, B9. Until a header is clicked, every level lists by name,
        /// folders first, the order the header shows. Quick Look reads it the
        /// same way, though its process registers no defaults: before, its rows
        /// came in no particular order.
        @Test func everyLevelListsByNameUntilAHeaderIsClicked() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let state = try await openArchive(in: dir, listSortedBy: makeDefaults())
            let root = try #require(state.root)

            #expect(names(state.displayedChildren(of: root)) == ["alpha", "Beta", "empty.txt", "zeta.txt"])
            let alpha = try #require(state.displayedChildren(of: root).first)
            #expect(names(state.displayedChildren(of: alpha)) == ["sub", "A.txt", "b.txt"])

            state.loadChildren()
            #expect(names(state.childItems ?? []) == ["alpha", "Beta", "empty.txt", "zeta.txt"], "the window's level differs")
        }

        /// #251 B9. A column chosen in the window or in Quick Look orders every
        /// level, not only the one the window shows.
        @Test func everyLevelFollowsTheChosenColumn() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let defaults = makeDefaults()
            defaults.set(ArchiveSortOrder.uncompressedSize.rawValue, forKey: Keys.defaultOrderColumn)
            defaults.set(false, forKey: Keys.defaultOrderColumnAscending)
            let state = try await openArchive(in: dir, listSortedBy: defaults)
            let root = try #require(state.root)

            // largest first; the entries of no size in the order of their paths
            #expect(names(state.displayedChildren(of: root)) == ["zeta.txt", "alpha", "Beta", "empty.txt"])
            let alpha = try #require(state.displayedChildren(of: root).first { $0.name == "alpha" })
            #expect(names(state.displayedChildren(of: alpha)) == ["b.txt", "A.txt", "sub"])
        }

        /// #251 B11. The window and Quick Look write a cell the same way: a file
        /// of zero bytes reads "0 bytes" in both (the preview left it empty), a
        /// folder shows no size, whether the archive has an entry for it or not.
        @Test func aCellReadsTheSameInTheWindowAndInQuickLook() {
            let empty = ArchiveItem(name: "empty.txt", virtualPath: "empty.txt", type: .file,
                                    compressedSize: 0, uncompressedSize: 0)
            #expect(EntryText.size(of: empty, packed: false) == "0 bytes")
            #expect(EntryText.size(of: empty, packed: true) == "0 bytes")
            #expect(EntryText.size(1_500) == "2 KB")
            for folder in [ArchiveItem(name: "docs", virtualPath: "docs", type: .directory),
                           ArchiveItem(name: "docs", virtualPath: "docs", type: .virtual),
                           ArchiveItem(name: "..", virtualPath: "/", type: .root)] {
                #expect(EntryText.size(of: folder, packed: false) == "", "\(folder.type) shows a size")
            }
            #expect(EntryText.permissions(0o100644) == "-rw-r--r--")
            #expect(EntryText.permissions(0o040755) == "drwxr-xr-x")
        }

        /// #251 B9, B10. The sort order and the columns move from the app's own
        /// settings into the app group once, so Quick Look reads what the window
        /// shows. A choice the app group holds already stays; nothing else moves.
        @Test func listSettingsMoveIntoTheAppGroupOnce() {
            let shared = makeDefaults()
            shared.set(false, forKey: Keys.showColumnModificationDate)
            let legacy: [String: Any] = [
                Keys.defaultOrderColumn: ArchiveSortOrder.uncompressedSize.rawValue,
                Keys.defaultOrderColumnAscending: false,
                Keys.showColumnPosixPermissions: true,
                Keys.showColumnModificationDate: true,
                Keys.showParentRow: true,
            ]

            Keys.moveListSettingsToSharedDefaults(from: legacy, to: shared)

            #expect(Keys.sortOrder(in: shared) == (.uncompressedSize, false))
            #expect(Keys.showsColumn(Keys.showColumnPosixPermissions, in: shared))
            #expect(!Keys.showsColumn(Keys.showColumnModificationDate, in: shared), "the app group's own choice was replaced")
            #expect(shared.object(forKey: Keys.showParentRow) == nil, "a setting of the window alone moved")
        }

        /// #251 B10. With nothing chosen, the sizes and the date show and the
        /// permissions don't, in the window and in Quick Look.
        @Test func theColumnsShownUntilOneIsHidden() {
            let shared = makeDefaults()
            #expect(Keys.showsColumn(Keys.showColumnCompressedSize, in: shared))
            #expect(Keys.showsColumn(Keys.showColumnUncompressedSize, in: shared))
            #expect(Keys.showsColumn(Keys.showColumnModificationDate, in: shared))
            #expect(!Keys.showsColumn(Keys.showColumnPosixPermissions, in: shared))
        }
    }
}
