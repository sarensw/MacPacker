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
    }
}
