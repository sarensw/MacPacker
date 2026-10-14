//
//  FolderExtractionTests.swift
//  Modules
//
//  Created by Stephan Arenswald on 09.08.26.
//

import Foundation
import Testing
@testable import Core

// MARK: - Extracting a selected folder to a destination

extension AllCoreTests {
    @MainActor struct FolderExtractionTests {

        // Regression for #175: selecting a macOS `.app` inside a Finder-compressed
        // zip and extracting it must leave exactly one bundle in the destination.
        // `ArchiveBatchResolver.expandDirectories` turns the selected folder into
        // every descendant so the engine can extract by index — but the extractor
        // then moved *each* expanded item to `destination/<leafName>`, flattening
        // the bundle into the target folder and dying on the first repeated leaf
        // name ("Resources", "Info.plist", "_CodeSignature", ...) with
        // "couldn't be moved ... an item with the same name already exists".
        //
        // The fixture `zip/minimalApp.zip` is a real, ad-hoc-signed app bundle
        // compressed the way Finder's "Compress" does it (see
        // `TestArchives/zip/make_minimal_app.sh`): symlinked framework versions,
        // an exec-bit binary, a `__MACOSX/` sidecar tree, and leaf names that
        // repeat across depths.
        @Test func extractAppBundleFolderKeepsBundleIntact() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let zipFolder = Bundle.module.url(forResource: "zip", withExtension: nil)!
            let url = zipFolder.appendingPathComponent("minimalApp.zip")

            state.open(url: url)
            try await state.openTask?.value

            // The fixture also carries a `__MACOSX/MinimalApp.app` sidecar tree,
            // so pin the lookup to the bundle sitting at the archive root.
            let rootID = try #require(state.root?.id)
            let appItem = try #require(
                state.entries.values.first(where: {
                    $0.name == "MinimalApp.app" && $0.isFolder && $0.parent == rootID
                }),
                "fixture should expose MinimalApp.app as a folder at the archive root"
            )

            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: destination) }

            let batches = try ArchiveBatchResolver().resolveBatches(
                for: [appItem],
                in: state.entries,
                using: ArchiveEngineSelector7zip()
            )

            let extractor = ArchiveExtractor(
                archiveEngineSelector: ArchiveEngineSelector7zip(),
                passwordResolver: { _ in nil }
            )
            _ = try await extractor.extract(batches: batches, to: destination)

            // 1. Only the bundle lands in the destination — no loose `Contents`,
            //    `Frameworks`, `Info.plist`, ... spilled next to it.
            let destContents = try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted()
            #expect(
                destContents == ["MinimalApp.app"],
                "destination should hold only the bundle, got \(destContents)"
            )

            // 2. The bundle is still a bundle: executable with its exec bit, the
            //    framework version symlinks, and the signature intact.
            let app = destination.appending(component: "MinimalApp.app")
            let binary = app.appending(path: "Contents/MacOS/MinimalApp")
            #expect(FileManager.default.fileExists(atPath: binary.path))

            let perms = (try FileManager.default.attributesOfItem(atPath: binary.path)[.posixPermissions]
                as? NSNumber)?.uint16Value ?? 0
            #expect(perms & 0o111 != 0, "app binary should keep an execute bit, got mode \(String(perms, radix: 8))")

            #expect(FileManager.default.fileExists(
                atPath: app.appending(path: "Contents/_CodeSignature/CodeResources").path
            ))

            let framework = app.appending(path: "Contents/Frameworks/Mini.framework")
            let currentLink = try? FileManager.default.destinationOfSymbolicLink(
                atPath: framework.appending(path: "Versions/Current").path
            )
            #expect(
                currentLink == "A",
                "Versions/Current should stay a symlink -> A, got \(String(describing: currentLink))"
            )
        }

        // #175 is not app-specific — any selected folder used to be flattened.
        // `nestedFolders.zip` is four plain levels deep with no bundle in sight.
        @Test func extractNestedFolderKeepsHierarchy() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let zipFolder = Bundle.module.url(forResource: "zip", withExtension: nil)!
            let url = zipFolder.appendingPathComponent("nestedFolders.zip")

            state.open(url: url)
            try await state.openTask?.value

            let rootID = try #require(state.root?.id)
            let folder = try #require(
                state.entries.values.first(where: { $0.name == "level1" && $0.parent == rootID })
            )

            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: destination) }

            let batches = try ArchiveBatchResolver().resolveBatches(
                for: [folder],
                in: state.entries,
                using: ArchiveEngineSelector7zip()
            )
            let extractor = ArchiveExtractor(
                archiveEngineSelector: ArchiveEngineSelector7zip(),
                passwordResolver: { _ in nil }
            )
            _ = try await extractor.extract(batches: batches, to: destination)

            let destContents = try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted()
            #expect(destContents == ["level1"], "only the selected folder belongs here, got \(destContents)")
            #expect(FileManager.default.fileExists(
                atPath: destination.appending(path: "level1/level2/level3/level4/level4").path
            ))
        }

        // The counterpart: an item selected *inside* a folder still lands bare in
        // the destination. The engine writes archive-relative paths into temp
        // (`<temp>/folder/README.md`), so the move has to reach for the item's own
        // url — moving whatever sits at the top of the temp directory would hand
        // the user a `folder/` they never asked for.
        @Test func extractNestedFileDropsItsAncestorFolders() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            let nestedFile = try #require(
                state.entries.values.first(where: { $0.virtualPath == "folder/README.md" })
            )

            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: destination) }

            let batches = try ArchiveBatchResolver().resolveBatches(
                for: [nestedFile],
                in: state.entries,
                using: ArchiveEngineSelector7zip()
            )
            let extractor = ArchiveExtractor(
                archiveEngineSelector: ArchiveEngineSelector7zip(),
                passwordResolver: { _ in nil }
            )
            _ = try await extractor.extract(batches: batches, to: destination)

            let destContents = try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted()
            #expect(destContents == ["README.md"], "expected the bare file, got \(destContents)")
        }

        // MARK: - A folder the archive has no entry for (#306)

        // A zip is a list of entries, and a folder is one of them only if
        // somebody wrote it. A download site's zip holds `Sample Kit/readme.html`
        // and nothing for `Sample Kit/`, so the row the window shows for the
        // folder is one `ArchiveLoader.buildTree` made up. No engine can be asked
        // for a folder like that and none says where it ended up, and the drag
        // settled for the first url the extraction did report: one of the files
        // inside, delivered under the folder's name. That is the document without
        // an extension, shown by Finder with a "?", of #306.
        //
        // `zip/noFolderEntries.zip` is the archive of that report in shape, down
        // to the tool that wrote it: see `TestArchives/zip/make_no_folder_entries.sh`.
        @Test(arguments: ZipReader.allCases)
        func dragOutFolderWithoutAnEntryDeliversTheFolder(reader: ZipReader) async throws {
            let (state, folder) = try await folderWithoutAnEntry("Sample Kit", reader: reader)

            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: destination) }

            // What the file promise hands over: the place Finder chose, ending in
            // the name the row has.
            let target = destination.appending(component: folder.name)
            try await state.fulfillDrag(item: folder, to: target)

            var isDirectory: ObjCBool = false
            #expect(
                FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory) && isDirectory.boolValue,
                "the dragged folder should arrive as a folder"
            )
            for file in ["readme.html", "Sample Kit.txt", "extras/licenses/license.txt"] {
                #expect(
                    FileManager.default.fileExists(atPath: target.appending(path: file).path),
                    "\(file) should come along inside it"
                )
            }
        }

        // One level is not the whole of it. `extras` holds nothing but `licenses`,
        // and the archive has no entry for that one either: where `extras` is can
        // only be told from a file two levels down.
        @Test(arguments: ZipReader.allCases)
        func dragOutFolderHoldingOnlyAFolderWithoutAnEntry(reader: ZipReader) async throws {
            let (state, folder) = try await folderWithoutAnEntry("extras", reader: reader)

            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: destination) }

            let target = destination.appending(component: folder.name)
            try await state.fulfillDrag(item: folder, to: target)

            #expect(FileManager.default.fileExists(atPath: target.appending(path: "licenses/license.txt").path))
        }

        // "Extract selected" is the same folder through the other door, and it
        // failed the other way round: the files were extracted, then left in the
        // temporary folder because their parent was selected and so was the one to
        // move — and it had no url to be moved from. The destination stayed empty
        // and the job reported done.
        @Test(arguments: ZipReader.allCases)
        func extractFolderWithoutAnEntryKeepsItsFiles(reader: ZipReader) async throws {
            let (state, folder) = try await folderWithoutAnEntry("Sample Kit", reader: reader)

            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: destination) }

            let batches = try ArchiveBatchResolver().resolveBatches(
                for: [folder],
                in: state.entries,
                using: reader.selector
            )
            let extractor = ArchiveExtractor(
                archiveEngineSelector: reader.selector,
                passwordResolver: { _ in nil }
            )
            _ = try await extractor.extract(batches: batches, to: destination)

            let destContents = try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted()
            #expect(destContents == ["Sample Kit"], "only the selected folder belongs here, got \(destContents)")
            for file in ["readme.html", "Sample Kit.txt", "extras/licenses/license.txt"] {
                #expect(
                    FileManager.default.fileExists(atPath: destination.appending(path: "Sample Kit/\(file)").path),
                    "\(file) should come along inside it"
                )
            }
        }

        /// Opens `zip/noFolderEntries.zip` and hands back its folder `name`,
        /// having made sure it is what the tests above are about: a folder the
        /// archive holds no entry for. A fixture rebuilt with folder entries would
        /// otherwise leave them passing for nothing.
        private func folderWithoutAnEntry(
            _ name: String,
            reader: ZipReader
        ) async throws -> (ArchiveState, ArchiveItem) {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: reader.selector)
            state.progressCenter = ExtractionProgressCenter()
            let zipFolder = Bundle.module.url(forResource: "zip", withExtension: nil)!

            state.open(url: zipFolder.appendingPathComponent("noFolderEntries.zip"))
            try await state.openTask?.value

            let folder = try #require(
                state.entries.values.first(where: { $0.name == name && $0.isFolder }),
                "fixture should show \(name) as a folder"
            )
            try #require(folder.type == .virtual, "\(name) should be a folder the archive has no entry for")
            return (state, folder)
        }
    }
}
