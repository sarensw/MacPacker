//
//  EngineTests.swift
//  Modules
//
//  Created by Stephan Arenswald on 31.03.26.
//

import Foundation
import Testing
@testable import Core

// MARK: - 1. Archive7ZipEngine Tests

extension AllCoreTests {
    @MainActor struct Archive7ZipEngineTests {

        // MARK: loadArchive

        @Test func loadArchiveZip() async throws {
            let engine = Archive7ZipEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            let result = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })

            #expect(result.items.count > 0)
            #expect(result.hasTree == false)
        }

        @Test func loadArchive7z() async throws {
            let engine = Archive7ZipEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.7z")

            let result = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })

            #expect(result.items.count > 0)
        }

        @Test func loadArchiveIsoReturnsEntries() async throws {
            let engine = Archive7ZipEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.iso")

            let result = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })

            #expect(result.items.count > 0)
        }

        @Test func loadArchiveDmgReturnsEntries() async throws {
            let engine = Archive7ZipEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.dmg")

            let result = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })

            #expect(result.items.count > 0)
        }

        @Test("Disk images report hasTree", arguments: [
            "dmg", "fat", "iso", "qcow2", "vdi", "vhd", "vhdx", "vmdk"
        ])
        func diskImageHasTree(ext: String) async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.\(ext)")

            state.open(url: url)
            try await state.openTask?.value

            // After loading through ArchiveState the tree is built and root has children
            #expect(state.root != nil)
            #expect(state.root!.children != nil)
            #expect(state.root!.children!.count > 0)
        }

        // MARK: extract(items:)

        @Test func extractSingleFileFromZip() async throws {
            let engine = Archive7ZipEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            let loadResult = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })
            let fileItem = loadResult.items.values.first(where: { $0.type == .file })!

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let extractResult = try await engine.extract(
                items: [fileItem],
                from: url,
                to: tempDir,
                passwordResolver: { _ in nil }
            )

            #expect(extractResult.urls.count == 1)
            let extractedURL = try extractResult.singleURL
            #expect(FileManager.default.fileExists(atPath: extractedURL.path))
        }

        @Test func extractMultipleItemsFromZip() async throws {
            let engine = Archive7ZipEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            let loadResult = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })
            let fileItems = Array(loadResult.items.values.filter { $0.type == .file })

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let extractResult = try await engine.extract(
                items: fileItems,
                from: url,
                to: tempDir,
                passwordResolver: { _ in nil }
            )

            #expect(extractResult.urls.count == fileItems.count)
        }

        // Regression for LB-555 (Zip-Slip / path traversal): a crafted archive whose
        // entries contain "../" or absolute paths must never write outside the
        // destination directory. The fixture `zip/zipslip.zip` has entries
        // "../escaped_rel.txt" and "/escaped_abs.txt" alongside a benign "safe.txt".
        @Test func extractionRejectsPathTraversal() async throws {
            let engine = Archive7ZipEngine()
            let zipFolder = Bundle.module.url(forResource: "zip", withExtension: nil)!
            let url = zipFolder.appendingPathComponent("zipslip.zip")

            let loadResult = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })
            let items = Array(loadResult.items.values)

            // Nested temp layout: anything written outside `dest` (i.e. elsewhere
            // under `parent`) is a traversal escape.
            let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let dest = parent.appendingPathComponent("dest")
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: parent) }

            _ = try await engine.extract(
                items: items,
                from: url,
                to: dest,
                passwordResolver: { _ in nil }
            )

            // Every regular file produced by the extraction must live under `dest`.
            let destPrefix = dest.standardizedFileURL.path + "/"
            let walker = FileManager.default.enumerator(
                at: parent,
                includingPropertiesForKeys: [.isRegularFileKey]
            )!
            while let fileURL = walker.nextObject() as? URL {
                let isRegularFile = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
                if isRegularFile {
                    #expect(
                        fileURL.standardizedFileURL.path.hasPrefix(destPrefix),
                        "Extracted file escaped the destination: \(fileURL.path)"
                    )
                }
            }
        }

        // Regression for #121: a macOS `.app` extracted from a zip with the 7-Zip
        // engine must keep its symbolic links and POSIX execute bit, otherwise the
        // bundle won't launch. The fixture `zip/appbundle.zip` mimics a bundle:
        // `payload/Contents/MacOS/bin` stored with mode 0755, and a symlink
        // `payload/Contents/MacOS/link -> bin`. Before the fix the bridge wrote the
        // symlink as a plain text file and dropped the exec bit.
        @Test func extractionPreservesSymlinksAndExecBit() async throws {
            let engine = Archive7ZipEngine()
            let zipFolder = Bundle.module.url(forResource: "zip", withExtension: nil)!
            let url = zipFolder.appendingPathComponent("appbundle.zip")

            let loadResult = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })
            let items = Array(loadResult.items.values)

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            _ = try await engine.extract(
                items: items,
                from: url,
                to: tempDir,
                passwordResolver: { _ in nil }
            )

            let macOSDir = tempDir.appendingPathComponent("payload/Contents/MacOS")
            let binURL = macOSDir.appendingPathComponent("bin")
            let linkURL = macOSDir.appendingPathComponent("link")

            // 1. The symlink must be a real symlink pointing at "bin" (before the fix
            //    it was a regular file whose contents were the string "bin", so
            //    destinationOfSymbolicLink throws and this is nil).
            let linkDestination = try? FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path)
            #expect(
                linkDestination == "bin",
                "link should be a symlink -> bin, got \(String(describing: linkDestination))"
            )

            // 2. The executable must keep its exec bit (fixture stores mode 0755).
            let attrs = try FileManager.default.attributesOfItem(atPath: binURL.path)
            let perms = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
            #expect(
                perms & 0o111 != 0,
                "bin should keep an execute bit, got mode \(String(perms, radix: 8))"
            )
        }

        @Test func extractEmptyItemsThrows() async throws {
            let engine = Archive7ZipEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            await #expect(throws: ArchiveError.self) {
                try await engine.extract(
                    items: [],
                    from: url,
                    to: tempDir,
                    passwordResolver: { _ in nil }
                )
            }
        }

        // MARK: statusStream

        @Test func statusStreamReturnsStream() async throws {
            let engine = Archive7ZipEngine()
            let stream = await engine.statusStream()

            // Verify we can get at least the initial idle status
            var gotStatus = false
            for await status in stream {
                if case .idle = status {
                    gotStatus = true
                }
                break
            }
            #expect(gotStatus)
        }

        // MARK: cancel

        @Test func cancelDoesNotCrash() async throws {
            let engine = Archive7ZipEngine()
            await engine.cancel()
            // If we reach here, cancel did not crash
        }
    }
}

// MARK: - 2. ArchiveXadEngine Tests

extension AllCoreTests {
    @MainActor struct ArchiveXadEngineTests {

        // MARK: loadArchive

        @Test func loadArchiveZipViaXad() async throws {
            let engine = ArchiveXadEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            let result = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })

            #expect(result.items.count > 0)
        }

        @Test func loadArchive7zViaXad() async throws {
            let engine = ArchiveXadEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.7z")

            let result = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })

            #expect(result.items.count > 0)
        }

        @Test func loadArchiveCabViaXad() async throws {
            let engine = ArchiveXadEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.cab")

            let result = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })

            #expect(result.items.count > 0)
        }

        // Regression: directory entries keep the "-1" unknown sentinel in
        // `uncompressedSize`, and the load-side total summed it verbatim — so
        // an archive with D directories reported D bytes short.
        @Test func loadArchiveViaXadReportsCorrectTotalSizeWithDirectories() async throws {
            let engine = ArchiveXadEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            let result = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })

            // Without a directory entry the assertion passes even unfixed.
            let dirCount = result.items.values.filter { $0.type == .directory }.count
            #expect(dirCount > 0, "fixture should contain at least one directory entry")

            let expected = result.items.values.reduce(Int64(0)) { sum, item in
                item.type == .file
                    ? sum + Int64(Swift.max(0, item.uncompressedSize))
                    : sum
            }

            #expect(
                result.uncompressedSize == expected,
                "total uncompressed size should sum file sizes only, got \(result.uncompressedSize) expected \(expected)"
            )
        }

        // MARK: extract(items:)

        @Test func extractSingleFileViaXad() async throws {
            let engine = ArchiveXadEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            let loadResult = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })
            let fileItem = loadResult.items.values.first(where: { $0.type == .file })!

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let extractResult = try await engine.extract(
                items: [fileItem],
                from: url,
                to: tempDir,
                passwordResolver: { _ in nil }
            )

            #expect(extractResult.urls.count == 1)
            let extractedURL = try extractResult.singleURL
            #expect(FileManager.default.fileExists(atPath: extractedURL.path))
        }

        // Reference behavior for #121: the XAD engine already preserves symlinks +
        // the exec bit. Locks that in so the 7-Zip fix has a matching baseline and
        // XAD can't silently regress. Same fixture as the 7-Zip test.
        @Test func extractionPreservesSymlinksAndExecBitViaXad() async throws {
            let engine = ArchiveXadEngine()
            let zipFolder = Bundle.module.url(forResource: "zip", withExtension: nil)!
            let url = zipFolder.appendingPathComponent("appbundle.zip")

            let loadResult = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })
            let items = Array(loadResult.items.values)

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            _ = try await engine.extract(
                items: items,
                from: url,
                to: tempDir,
                passwordResolver: { _ in nil }
            )

            let macOSDir = tempDir.appendingPathComponent("payload/Contents/MacOS")
            let linkDestination = try? FileManager.default.destinationOfSymbolicLink(
                atPath: macOSDir.appendingPathComponent("link").path
            )
            #expect(linkDestination == "bin")

            let attrs = try FileManager.default.attributesOfItem(
                atPath: macOSDir.appendingPathComponent("bin").path
            )
            let perms = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
            #expect(perms & 0o111 != 0)
        }

        @Test func extractDirectoryItemViaXad() async throws {
            let engine = ArchiveXadEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            let loadResult = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })
            let dirItem = loadResult.items.values.first(where: { $0.type == .directory })!

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let extractResult = try await engine.extract(
                items: [dirItem],
                from: url,
                to: tempDir,
                passwordResolver: { _ in nil }
            )

            #expect(extractResult.urls.count == 1)
            let extractedURL = try extractResult.singleURL
            var isDir: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: extractedURL.path, isDirectory: &isDir))
            #expect(isDir.boolValue)
        }

        // MARK: extract(_ url:, to:)

        @Test func fullExtractionViaXad() async throws {
            let engine = ArchiveXadEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            try await engine.extract(url, to: tempDir, passwordResolver: { _ in nil })

            let contents = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
            #expect(contents.count > 0)
        }

        // MARK: statusStream / cancel

        @Test func xadStatusStreamReturnsStream() async throws {
            let engine = ArchiveXadEngine()
            let stream = await engine.statusStream()

            var gotStatus = false
            for await status in stream {
                if case .idle = status {
                    gotStatus = true
                }
                break
            }
            #expect(gotStatus)
        }

        @Test func xadCancelDoesNotCrash() async throws {
            let engine = ArchiveXadEngine()
            await engine.cancel()
        }
    }
}

// MARK: - 3. ArchiveSwcEngine Tests

extension AllCoreTests {
    @MainActor struct ArchiveSwcEngineTests {

        // MARK: loadArchive

        @Test func loadArchiveTarLz4() async throws {
            let engine = ArchiveSwcEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.tar.lz4")

            let result = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })

            // SWC engine reports 1 entry: the inner decompressed file
            #expect(result.items.count == 1)
            let entry = result.items.values.first!
            #expect(entry.name == "defaultArchive.tar")
        }

        @Test func loadArchiveTlz4() async throws {
            let engine = ArchiveSwcEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.tlz4")

            let result = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })

            #expect(result.items.count == 1)
            // "defaultArchive.tlz4" stripped of extension becomes "defaultArchive"
            let entry = result.items.values.first!
            #expect(entry.name == "defaultArchive")
        }

        // MARK: stripFileExtension (indirectly through loadArchive)

        @Test("Strip file extension mapping", arguments: [
            ("tar.lz4", "defaultArchive.tar"),
            ("tlz4", "defaultArchive")
        ])
        func stripFileExtension(arg: (String, String)) async throws {
            let ext = arg.0
            let expectedName = arg.1
            let engine = ArchiveSwcEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.\(ext)")

            let result = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })

            let entry = result.items.values.first!
            #expect(entry.name == expectedName)
        }

        // MARK: extract(items:)

        @Test func extractFromTarLz4() async throws {
            let engine = ArchiveSwcEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.tar.lz4")

            let loadResult = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })
            let item = loadResult.items.values.first!

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let extractResult = try await engine.extract(
                items: [item],
                from: url,
                to: tempDir,
                passwordResolver: { _ in nil }
            )

            #expect(extractResult.urls.count == 1)
            // Verify the decompressed file exists on disk
            let decompressedPath = tempDir.appendingPathComponent("defaultArchive.tar")
            #expect(FileManager.default.fileExists(atPath: decompressedPath.path))
        }

        // MARK: extract(_ url:, to:)

        @Test func fullExtractionSwc() async throws {
            let engine = ArchiveSwcEngine()
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.tar.lz4")

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            try await engine.extract(url, to: tempDir, passwordResolver: { _ in nil })

            let decompressedPath = tempDir.appendingPathComponent("defaultArchive.tar")
            #expect(FileManager.default.fileExists(atPath: decompressedPath.path))
        }

        // MARK: statusStream / cancel

        @Test func swcStatusStreamReturnsStream() async throws {
            let engine = ArchiveSwcEngine()
            let stream = await engine.statusStream()

            var gotStatus = false
            for await status in stream {
                if case .idle = status {
                    gotStatus = true
                }
                break
            }
            #expect(gotStatus)
        }

        @Test func swcCancelDoesNotCrash() async throws {
            let engine = ArchiveSwcEngine()
            await engine.cancel()
        }
    }
}

// MARK: - 4. ArchiveExtractor Tests

extension AllCoreTests {
    @MainActor struct ArchiveExtractorTests {

        // MARK: extract(batch:)

        @Test func extractSingleBatch() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            let fileItem = state.entries.values.first(where: { $0.type == .file })!

            let batchResolver = ArchiveBatchResolver()
            let batches = try batchResolver.resolveBatches(
                for: [fileItem],
                in: state.entries,
                using: ArchiveEngineSelector7zip()
            )
            let batch = batches.first!

            let extractor = ArchiveExtractor(
                archiveEngineSelector: ArchiveEngineSelector7zip(),
                passwordResolver: { _ in nil }
            )
            let result = try await extractor.extract(batch: batch)

            #expect(FileManager.default.fileExists(atPath: result.url.path))
            #expect(FileManager.default.fileExists(atPath: result.tempDir.path))
        }

        // MARK: extract(batches:to:)

        @Test func extractBatchesToDestination() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            let fileItems = Array(state.entries.values.filter { $0.type == .file })
            #expect(fileItems.count > 0)

            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: destination) }

            let batchResolver = ArchiveBatchResolver()
            let batches = try batchResolver.resolveBatches(
                for: fileItems,
                in: state.entries,
                using: ArchiveEngineSelector7zip()
            )

            let extractor = ArchiveExtractor(
                archiveEngineSelector: ArchiveEngineSelector7zip(),
                passwordResolver: { _ in nil }
            )
            let result = try await extractor.extract(batches: batches, to: destination)

            #expect(result.urls.count == fileItems.count)
            #expect(result.tempDirs.count > 0)

            // Verify files were moved to destination
            let destContents = try FileManager.default.contentsOfDirectory(atPath: destination.path)
            #expect(destContents.count > 0)
        }

        // MARK: extractAll

        @Test func extractAllToDestination() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: destination) }

            guard let root = state.root,
                  let (archiveTypeId, archiveUrl) = ArchiveSupportUtilities().findHandlerAndUrl(for: root, in: state.entries)
            else {
                throw ArchiveError.extractionFailed("Could not resolve archive info for extractAll")
            }

            let extractor = ArchiveExtractor(
                archiveEngineSelector: ArchiveEngineSelector7zip(),
                passwordResolver: { _ in nil }
            )
            try await extractor.extractAll(archiveUrl, archiveTypeId: archiveTypeId, to: destination)
        }

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
            #expect(currentLink == "A", "Versions/Current should stay a symlink -> A, got \(String(describing: currentLink))")
        }

        // MARK: error cases

        @Test func extractBatchWithNoItemsThrows() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            state.open(url: url)
            try await state.openTask?.value

            let emptyBatch = ResolvedBatch(
                archiveURL: url,
                engineType: .`7zip`,
                items: []
            )

            let extractor = ArchiveExtractor(
                archiveEngineSelector: ArchiveEngineSelector7zip(),
                passwordResolver: { _ in nil }
            )

            await #expect(throws: ArchiveError.self) {
                try await extractor.extract(batch: emptyBatch)
            }
        }
    }
}

// MARK: - 5. ArchiveExtractionResult Tests

extension AllCoreTests {
    @MainActor struct ArchiveExtractionResultTests {

        // MARK: singleURL

        @Test func singleURLWithOneEntry() throws {
            let id = UUID()
            let url = URL(fileURLWithPath: "/tmp/test_file.txt")
            let result = ArchiveExtractionResult(urlsByItemID: [id: url])

            let single = try result.singleURL
            #expect(single == url)
        }

        @Test func singleURLWithZeroEntriesThrows() {
            let result = ArchiveExtractionResult(urlsByItemID: [:])

            #expect(throws: ArchiveError.self) {
                try result.singleURL
            }
        }

        @Test func singleURLWithMultipleEntriesThrows() {
            let result = ArchiveExtractionResult(urlsByItemID: [
                UUID(): URL(fileURLWithPath: "/tmp/a.txt"),
                UUID(): URL(fileURLWithPath: "/tmp/b.txt")
            ])

            #expect(throws: ArchiveError.self) {
                try result.singleURL
            }
        }

        // MARK: subscript

        @Test func subscriptByArchiveItem() {
            let item = ArchiveItem(name: "test.txt", type: .file)
            let url = URL(fileURLWithPath: "/tmp/test.txt")
            let result = ArchiveExtractionResult(urlsByItemID: [item.id: url])

            #expect(result[item] == url)
        }

        @Test func subscriptByUUID() {
            let id = UUID()
            let url = URL(fileURLWithPath: "/tmp/test.txt")
            let result = ArchiveExtractionResult(urlsByItemID: [id: url])

            #expect(result[id: id] == url)
        }

        @Test func subscriptByMissingItemReturnsNil() {
            let result = ArchiveExtractionResult(urlsByItemID: [:])
            let item = ArchiveItem(name: "missing.txt", type: .file)

            #expect(result[item] == nil)
        }

        @Test func subscriptByMissingUUIDReturnsNil() {
            let result = ArchiveExtractionResult(urlsByItemID: [:])

            #expect(result[id: UUID()] == nil)
        }
    }
}

// MARK: - 6. Password-Protected Archive Tests

extension AllCoreTests {
    @MainActor struct PasswordProtectedArchiveTests {

        // MARK: 7zip engine with password

        @Test func loadPasswordProtectedZipWith7zip() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            // Was defaultArchive_password.zip, whose password nobody knows —
            // these tests only ever "passed" because a wrong password used to
            // write empty files and report success. Fixture since deleted.
            let zipFolder = Bundle.module.url(forResource: "password", withExtension: nil)!
            let url = zipFolder.appendingPathComponent("zip_zipcrypto.zip")

            state.passwordProvider = { _ in
                return "password"
            }

            state.open(url: url)
            try await state.openTask?.value

            #expect(state.entries.count > 0)
            #expect(state.root != nil)
        }

        @Test func extractPasswordProtectedFileWith7zip() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            // Was defaultArchive_password.zip, whose password nobody knows —
            // these tests only ever "passed" because a wrong password used to
            // write empty files and report success. Fixture since deleted.
            let zipFolder = Bundle.module.url(forResource: "password", withExtension: nil)!
            let url = zipFolder.appendingPathComponent("zip_zipcrypto.zip")

            state.passwordProvider = { _ in
                return "password"
            }

            state.open(url: url)
            try await state.openTask?.value

            #expect(state.entries.count > 0)

            let fileItem = state.entries.values.first(where: { $0.type == .file })!
            let extractedURL = try await state.extractToTemp(item: fileItem)
            #expect(FileManager.default.fileExists(atPath: extractedURL.path))
        }

        // MARK: XAD engine with password

        @Test func loadPasswordProtectedZipWithXad() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelectorXad())
            // Was defaultArchive_password.zip, whose password nobody knows —
            // these tests only ever "passed" because a wrong password used to
            // write empty files and report success. Fixture since deleted.
            let zipFolder = Bundle.module.url(forResource: "password", withExtension: nil)!
            let url = zipFolder.appendingPathComponent("zip_zipcrypto.zip")

            state.passwordProvider = { _ in
                return "password"
            }

            state.open(url: url)
            try await state.openTask?.value

            #expect(state.entries.count > 0)
            #expect(state.root != nil)
        }

        // MARK: Password cancelled

        @Test func passwordCancelledThrows7zip() async throws {
            let engine = Archive7ZipEngine()
            // Was defaultArchive_password.zip, whose password nobody knows —
            // these tests only ever "passed" because a wrong password used to
            // write empty files and report success. Fixture since deleted.
            let zipFolder = Bundle.module.url(forResource: "password", withExtension: nil)!
            let url = zipFolder.appendingPathComponent("zip_zipcrypto.zip")

            // Load archive to get entries (loading does not need password for zip)
            let loadResult = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })
            let fileItem = loadResult.items.values.first(where: { $0.type == .file })!

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // Extraction requires password; returning nil should trigger passwordCancelled
            let passwordResolver: ArchivePasswordResolver = { _ in nil }

            await #expect(throws: ArchiveError.self) {
                try await engine.extract(
                    items: [fileItem],
                    from: url,
                    to: tempDir,
                    passwordResolver: passwordResolver
                )
            }
        }

        @Test func passwordCancelledThrowsXad() async throws {
            let engine = ArchiveXadEngine()
            // Was defaultArchive_password.zip, whose password nobody knows —
            // these tests only ever "passed" because a wrong password used to
            // write empty files and report success. Fixture since deleted.
            let zipFolder = Bundle.module.url(forResource: "password", withExtension: nil)!
            let url = zipFolder.appendingPathComponent("zip_zipcrypto.zip")

            let loadResult = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })
            let fileItem = loadResult.items.values.first(where: { $0.type == .file })!

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let passwordResolver: ArchivePasswordResolver = { _ in nil }

            await #expect(throws: ArchiveError.self) {
                try await engine.extract(
                    items: [fileItem],
                    from: url,
                    to: tempDir,
                    passwordResolver: passwordResolver
                )
            }
        }
    }
}
