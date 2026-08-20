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

        // Regression for #189: when macOS cannot store a file's xattrs and resource
        // fork in place — a FAT stick, an SMB share — it splits them into a sibling
        // `._name` file in AppleDouble format. That sidecar is then an ordinary
        // file, so any archiver walking the folder stores it; nothing about it is
        // zip-specific. Written out as a file it adds an entry to the tree, which
        // inside a signed `.app` breaks the code-signature seal — the reported
        // archive extracted to a bundle macOS called damaged. The sidecar has to be
        // unpacked into the entry it describes and removed.
        //
        // `._` is a convention, not a reservation, so the fixture also carries
        // files that only look like sidecars and must survive untouched. See
        // `zip/make_appledouble.sh` in MacPacker-TestArchives for the full matrix.
        @Test func extractionUnpacksAppleDoubleSidecarsAndSparesDecoys() async throws {
            let engine = Archive7ZipEngine()
            let zipFolder = Bundle.module.url(forResource: "zip", withExtension: nil)!
            let url = zipFolder.appendingPathComponent("appledouble.zip")

            let loadResult = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })
            let items = Array(loadResult.items.values)

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // "Extract here" writes straight into a folder of the user's own files,
            // and "Extract to folder" reuses an existing folder on a second run — so
            // the destination is not always empty. Plant a file the archive does not
            // contain, whose name a sidecar in it happens to describe.
            let fm = FileManager.default
            let squatter = tempDir.appendingPathComponent("payload/orphan.bin")
            try fm.createDirectory(at: squatter.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("a file the user already had\n".utf8).write(to: squatter)

            _ = try await engine.extract(
                items: items,
                from: url,
                to: tempDir,
                passwordResolver: { _ in nil }
            )

            let payload = tempDir.appendingPathComponent("payload")

            // 1. Both real sidecars are consumed, and both targets come out carrying
            //    what the sidecar held. The two differ only in storage order —
            //    `._icon.png` precedes its file, `._helper` follows it — because an
            //    extractor that unpacks a sidecar the moment it reads it handles
            //    only the second. Order means nothing in a zip, and `._x` sorts
            //    before `x`, so the first form is what plain `zip -r` produces.
            for target in ["Contents/Resources/icon.png", "Contents/MacOS/helper"] {
                let fileURL = payload.appendingPathComponent(target)
                let sidecarURL = fileURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("._" + fileURL.lastPathComponent)

                #expect(
                    fm.fileExists(atPath: sidecarURL.path) == false,
                    "\(sidecarURL.lastPathComponent) should have been unpacked into \(target) and removed"
                )
                #expect(
                    extendedAttribute("com.apple.ResourceFork", at: fileURL)
                        == Data("RESOURCE-FORK-PAYLOAD".utf8),
                    "\(target) should carry the resource fork from its sidecar"
                )
                #expect(
                    extendedAttribute("com.macpacker.test", at: fileURL)
                        == Data("appledouble-fixture".utf8),
                    "\(target) should carry the xattr from its sidecar"
                )
            }

            // 2. Unpacking metadata must not touch the data fork. The fixture stores
            //    a 1x1 PNG; applying the sidecar with the wrong copyfile flags would
            //    overwrite these bytes with the AppleDouble instead.
            let iconData = try Data(contentsOf: payload.appendingPathComponent("Contents/Resources/icon.png"))
            #expect(iconData.count == 70, "icon.png data fork should be untouched, got \(iconData.count) bytes")
            #expect(iconData.starts(with: [0x89, 0x50, 0x4E, 0x47]), "icon.png should still be a PNG")

            // 3. A file that merely starts with `._` is a normal file. This one is
            //    plain text and its sibling exists, so only its content separates it
            //    from the two above — deleting it on the name alone loses user data.
            let decoy = payload.appendingPathComponent("._notadouble.txt")
            #expect(fm.fileExists(atPath: decoy.path), "._notadouble.txt is not AppleDouble and must survive")
            #expect(
                (try? Data(contentsOf: decoy)) == Data("A real file that merely starts with dot-underscore.\n".utf8),
                "._notadouble.txt should come out byte-identical"
            )

            // 4. Directories carry extended attributes too, and macOS emits
            //    `._Resources` beside a bundle's `Resources/` as readily as it does
            //    for a file. Inside a bundle such a sidecar breaks the seal the same
            //    way, so it has to go the same way — and `Resources/` has to survive
            //    as a directory, with its contents untouched.
            let resources = payload.appendingPathComponent("Contents/Resources")
            #expect(
                fm.fileExists(atPath: payload.appendingPathComponent("Contents/._Resources").path) == false,
                "._Resources describes the Resources directory and should have been unpacked into it"
            )
            var resourcesIsDirectory: ObjCBool = false
            #expect(
                fm.fileExists(atPath: resources.path, isDirectory: &resourcesIsDirectory)
                    && resourcesIsDirectory.boolValue,
                "Resources should still be a directory"
            )
            #expect(
                extendedAttribute("com.macpacker.dir", at: resources) == Data("appledouble-fixture".utf8),
                "Resources should carry the xattr from its sidecar"
            )

            // 5. A real AppleDouble with no sibling stays put. `copyfile` with
            //    COPYFILE_UNPACK happily creates a missing destination, which would
            //    invent `orphan.bin` — a file the archive never contained.
            #expect(
                fm.fileExists(atPath: payload.appendingPathComponent("._orphan.bin").path),
                "._orphan.bin has no target to unpack into and must survive"
            )
            // The planted file is not ours: the extraction never wrote it, so its
            // contents and its metadata both have to come out exactly as they went in.
            #expect(
                (try? Data(contentsOf: squatter)) == Data("a file the user already had\n".utf8),
                "a pre-existing orphan.bin must not be rewritten by the extraction"
            )
            #expect(
                extendedAttribute("com.macpacker.test", at: squatter) == nil,
                "._orphan.bin must not fold its metadata into a file the extraction did not create"
            )
        }

        // The general form of the guard above, and the one that does not depend on
        // knowing which name is dangerous. An extraction owns what it writes and
        // nothing else — but the destination is not always empty: "Extract here"
        // writes into a folder of the user's own files, and "Extract to folder"
        // reuses an existing folder on a second run. Post-processing passes are
        // where this goes wrong, because they run over paths rather than over the
        // stream they just wrote; the AppleDouble drain did exactly that.
        //
        // Deliberately not about name collisions: an entry that matches a file
        // already there does replace it, the same as `ditto`. This is about the
        // files an archive never mentions at all.
        @Test func extractionLeavesFilesItDidNotCreateAlone() async throws {
            let engine = Archive7ZipEngine()
            let zipFolder = Bundle.module.url(forResource: "zip", withExtension: nil)!
            let url = zipFolder.appendingPathComponent("appledouble.zip")

            let loadResult = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })
            let items = Array(loadResult.items.values)

            let fm = FileManager.default
            let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? fm.removeItem(at: tempDir) }

            // Bystanders, none of them named by the archive, planted in the very
            // directories the extraction writes into. The `._userfile.dat` pair is
            // the sharp one: a complete AppleDouble pair the user already had, which
            // an extractor working from names rather than from what it wrote would
            // happily fold together and delete half of.
            let bystanders: [(path: String, contents: String)] = [
                ("payload/orphan.bin", "the file an archive sidecar names but never carries\n"),
                ("payload/userfile.dat", "a file of the user's own\n"),
                ("payload/Contents/Resources/keepme.png", "a bystander where the sidecars land\n")
            ]
            // Planting that last one also makes `payload/Contents/Resources/` a
            // directory the user already had. The archive carries `._Resources`
            // describing exactly that path, and writes `icon.png` inside it — but
            // `CreateComplexDir` is mkdir -p and reports success on a directory that
            // was already there, so writing into it must not be mistaken for making
            // it.
            for bystander in bystanders {
                let fileURL = tempDir.appendingPathComponent(bystander.path)
                try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(bystander.contents.utf8).write(to: fileURL)
            }

            // `userfile.dat` gets a real sidecar of its own, packed by the same
            // system call that unpacks one — plain bytes would not do, because a
            // destination-walking implementation would reject them on content alone
            // and this would pass without proving anything. Both halves are the
            // user's, and the extraction has no business reading either: the drain
            // works from the list of sidecars it wrote, never from what it finds on
            // disk. Fold these together and the user loses `._userfile.dat`.
            let userFile = tempDir.appendingPathComponent("payload/userfile.dat")
            let userSidecar = tempDir.appendingPathComponent("payload/._userfile.dat")
            setExtendedAttribute("com.macpacker.userown", Data("the user's own metadata".utf8), at: userFile)
            #expect(
                copyfile(userFile.path, userSidecar.path, nil,
                         copyfile_flags_t(COPYFILE_PACK | COPYFILE_XATTR | COPYFILE_ACL)) == 0,
                "could not pack the bystander sidecar"
            )
            let userSidecarBytes = try Data(contentsOf: userSidecar)
            let userFileXattr = extendedAttribute("com.macpacker.userown", at: userFile)
            #expect(userSidecarBytes.starts(with: [0x00, 0x05, 0x16, 0x07]), "bystander sidecar should be AppleDouble")
            #expect(userFileXattr != nil)

            _ = try await engine.extract(
                items: items,
                from: url,
                to: tempDir,
                passwordResolver: { _ in nil }
            )

            for bystander in bystanders {
                let fileURL = tempDir.appendingPathComponent(bystander.path)
                #expect(
                    (try? Data(contentsOf: fileURL)) == Data(bystander.contents.utf8),
                    "\(bystander.path) was not written by this extraction and must come out untouched"
                )
                #expect(
                    extendedAttribute("com.macpacker.test", at: fileURL) == nil,
                    "\(bystander.path) must not receive metadata from the archive"
                )
            }

            // Neither half of the user's own AppleDouble pair may be read, rewritten
            // or removed — not the sidecar, and not the metadata it describes.
            #expect(
                (try? Data(contentsOf: userSidecar)) == userSidecarBytes,
                "a sidecar the extraction did not write must come out byte-identical"
            )
            #expect(
                extendedAttribute("com.macpacker.userown", at: userFile) == userFileXattr,
                "userfile.dat must keep the metadata it already had"
            )

            // The directory the bystander sits in was the user's, not ours.
            let resources = tempDir.appendingPathComponent("payload/Contents/Resources")
            #expect(
                extendedAttribute("com.macpacker.dir", at: resources) == nil,
                "a directory the extraction only wrote into must not collect metadata from ._Resources"
            )
            #expect(
                fm.fileExists(atPath: tempDir.appendingPathComponent("payload/Contents/._Resources").path),
                "._Resources has no directory of ours to fold into and must stay put"
            )
        }

        // Gatekeeper's verdict on a downloaded file lives in com.apple.quarantine,
        // and copyfile's COPYFILE_UNPACK replaces a target's extended attributes
        // rather than merging into them. So an archive shipping `Evil.app` beside a
        // `._Evil.app` that carries no quarantine would have this extraction lift
        // the quarantine off the bundle — the archive deciding, through metadata
        // alone, that its own contents are trusted. Quarantine is the system's call,
        // never the archive's.
        //
        // Extracting twice into one destination is what makes this observable: the
        // second pass reopens the existing file with O_TRUNC, which keeps the inode
        // and the attributes on it, so a quarantine set between the passes is still
        // there when the sidecar is unpacked over it.
        @Test func extractionDoesNotLetAnArchiveClearQuarantine() async throws {
            let engine = Archive7ZipEngine()
            let zipFolder = Bundle.module.url(forResource: "zip", withExtension: nil)!
            let url = zipFolder.appendingPathComponent("appledouble.zip")

            let loadResult = try await engine.loadArchive(url: url, passwordResolver: { _ in nil })
            let items = Array(loadResult.items.values)

            let fm = FileManager.default
            let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: tempDir) }

            for _ in 0..<1 {
                _ = try await engine.extract(items: items, from: url, to: tempDir,
                                             passwordResolver: { _ in nil })
            }

            // Stand in for what the system does to anything MacPacker writes.
            let helper = tempDir.appendingPathComponent("payload/Contents/MacOS/helper")
            try #require(fm.fileExists(atPath: helper.path))
            let verdict = Data("0083;68a1b2c3;Safari;E7A1-CAFE".utf8)
            setExtendedAttribute("com.apple.quarantine", verdict, at: helper)

            _ = try await engine.extract(items: items, from: url, to: tempDir,
                                         passwordResolver: { _ in nil })

            // The sidecar was unpacked again over the same file — proving the pass
            // ran — but it has no say over the quarantine that was already there.
            #expect(
                extendedAttribute("com.macpacker.test", at: helper) == Data("appledouble-fixture".utf8),
                "the sidecar should still have been unpacked on the second pass"
            )
            #expect(
                extendedAttribute("com.apple.quarantine", at: helper) == verdict,
                "an archive must not be able to clear Gatekeeper's quarantine"
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

/// Reads one extended attribute, or nil when the file does not carry it.
/// `FileManager` exposes no API for these, and the AppleDouble regression above
/// is entirely about whether they arrive — including `com.apple.ResourceFork`,
/// which is how macOS stores a resource fork.
private func extendedAttribute(_ name: String, at url: URL) -> Data? {
    let size = getxattr(url.path, name, nil, 0, 0, 0)
    guard size >= 0 else { return nil }
    guard size > 0 else { return Data() }

    var buffer = Data(count: size)
    let read = buffer.withUnsafeMutableBytes {
        getxattr(url.path, name, $0.baseAddress, size, 0, 0)
    }
    guard read == size else { return nil }
    return buffer
}

/// Sets one extended attribute. The counterpart to `extendedAttribute`, for
/// seeding metadata a test then asserts survives untouched.
private func setExtendedAttribute(_ name: String, _ value: Data, at url: URL) {
    let result = value.withUnsafeBytes {
        setxattr(url.path, name, $0.baseAddress, value.count, 0, 0)
    }
    precondition(result == 0, "setxattr \(name) failed on \(url.path)")
}
