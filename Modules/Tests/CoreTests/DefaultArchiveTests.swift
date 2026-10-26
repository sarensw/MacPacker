//
//  DefaultArchiveTests.swift
//  Modules
//
//  Created by Stephan Arenswald on 12.12.25.
//

import Foundation
import Testing
@testable import Core

extension AllCoreTests {
    @MainActor struct DefaultArchiveTests {
        
        @Test("Test all defaultArchives on SWC", arguments: [
            // ext, id, folder entries
            ("tlz4", "tar", true),
            ("tar.lz4", "tar", true)
        ])
        func testAllSwcEngine(arg: (String, String, Bool)) async throws {
            let ext = arg.0
            let id = arg.1
            let folderEntries = arg.2
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelectorSwc())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            
            let url = folderURL.appendingPathComponent("defaultArchive.\(ext)")
            
            state.open(url: url)
            try await state.openTask?.value
            
            #expect(state.type?.id == id)
            #expect(state.entries.count == 2) // 1 item + root
            #expect(state.root === state.selectedItem)
        }
        
        @Test("Test all defaultArchives on 7zip", arguments: [
            // ext, id, entries (incl. root), root children
            ("7z", "7zip", 5, 2),
            // arj/cab/lzh store no folder entries — buildTree synthesizes the
            // folder, so the entry count matches the formats that do store it
            ("arj", "arj", 5, 2),
            ("ar", "ar", 4, 3), // `ar` archives do not store folders, only folder paths
            ("cab", "cab", 5, 2),
            ("cpio", "cpio", 5, 2),
            ("lzh", "lha", 5, 2),
            ("rar", "rar", 5, 2),
            ("tar", "tar", 5, 2),
            ("xar", "xar", 6, 3), // additional `[TOC].xml`
            ("zip", "zip", 5, 2),
            // zip-based package format — detected as plain zip. Unlike the zip
            // fixture it stores no folder entry, so buildTree synthesizes it
            ("jar", "zip", 5, 2),
            // installers
            ("rpm", "rpm", 2, 1),
            // a self-extracting 7z: the archive behind the program, not the program
            ("exe", "msapp", 5, 2),
            // disk images
            ("dmg", "dmg", 5, 2),
            ("fat", "fat", 5, 2),
            ("iso", "iso", 5, 2),
            ("qcow2", "qcow2", 5, 2),
            ("squashfs", "squashfs", 5, 2),
            ("vdi", "vdi", 5, 2),
            ("vhd", "vhd", 5, 2),
            ("vhdx", "vhdx", 5, 2),
            ("vmdk", "vmdk", 5, 2),
            // compounds
            ("tar.bz2", "tar", 5, 2),
            ("tar.gz", "tar", 5, 2),
            ("tar.lzma", "tar", 5, 2),
            ("tar.xz", "tar", 5, 2),
            ("tar.Z", "tar", 5, 2),
            // comounds with one ending
            ("tbz2", "tar", 5, 2),
            ("tgz", "tar", 5, 2),
            ("tlzma", "tar", 5, 2),
            ("txz", "tar", 5, 2),
            ("taz", "tar", 5, 2)
        ])
        func testAll7zipEngine(arg: (String, String, Int, Int)) async throws {
            let ext = arg.0
            let id = arg.1
            let entries = arg.2
            let rootChildren = arg.3
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            
            let url = folderURL.appendingPathComponent("defaultArchive.\(ext)")
            
            state.open(url: url)
            try await state.openTask?.value
            
            print("debug break point")
            
            #expect(state.type?.id == id)
            #expect(state.entries.count == entries)
            #expect(state.root?.children?.count == rootChildren)
            #expect(state.root === state.selectedItem)
        }
        
        /// A deb lists its members, not a lone "unknown". dpkg-deb names the
        /// first member `debian-binary`, and 7-Zip then offers the compressed
        /// `data.tar.*` as the main subfile, whose one nameless stream was all
        /// that showed. fpm names it `debian-binary/`, which 7-Zip reads as a
        /// plain ar, so that deb always listed its members.
        @Test(arguments: [
            ("defaultarchive-dpkg.deb", ["control.tar.xz", "data.tar.xz"]),
            ("defaultarchive.deb", ["control.tar.gz", "data.tar.gz", "debian-binary"])
        ])
        func debListsItsMembers(arg: (String, [String])) async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let url = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
                .appendingPathComponent(arg.0)

            state.open(url: url)
            try await state.openTask?.value

            let names = state.root?.children?.compactMap { state.entries[$0]?.name }.sorted()
            #expect(names == arg.1)
        }
        
        /// An entry the archive gives no name lists and extracts under the name
        /// 7-Zip's own client gives it, not as "unknown": the archive's, less the
        /// compression extension. bzip2, xz, lzma and compress store no name, and
        /// gzip only optionally. An rpm's payload is such a stream, one level in,
        /// so it is named after the payload the rpm describes.
        @Test(arguments: [
            ("compressed/hello world.txt.gz", "hello world.txt"),
            ("compressed/hello world.txt.bz2", "hello world.txt"),
            ("compressed/hello world.txt.xz", "hello world.txt"),
            ("compressed/hello world.txt.lzma", "hello world.txt"),
            ("compressed/hello world.txt.Z", "hello world.txt"),
            ("defaultArchives/defaultArchive.rpm", "defaultArchive-1.0-1.aarch64.cpio")
        ])
        func namelessEntryIsNamedAfterTheArchive(arg: (String, String)) async throws {
            let parts = arg.0.split(separator: "/")
            let url = Bundle.module.url(forResource: String(parts[0]), withExtension: nil)!
                .appendingPathComponent(String(parts[1]))

            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.open(url: url)
            try await state.openTask?.value
            #expect(state.root?.children?.compactMap { state.entries[$0]?.name } == [arg.1])

            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: destination) }
            try await Archive7ZipEngine().extract(url, to: destination, passwordResolver: { _ in nil })
            let written = try FileManager.default.contentsOfDirectory(atPath: destination.path)
            #expect(written == [arg.1])
        }

        @Test("Test all defaultArchives on xad", arguments: [
            ("zip", "zip"),
            ("7z", "7zip"),
            ("tbz2", "tar"),
            ("tar.bz2", "tar"),
            ("cab", "cab"), // stores no folder entry — buildTree synthesizes it
            ("cpio", "cpio")
        ])
        func testAllXadEngine(arg: (String, String)) async throws {
            let ext = arg.0
            let id = arg.1
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelectorXad())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            
            let url = folderURL.appendingPathComponent("defaultArchive.\(ext)")
            
            state.open(url: url)
            try await state.openTask?.value
            
            #expect(state.type?.id == id)
            #expect(state.entries.count == 5)
            #expect(state.root?.children?.count == 2)
            #expect(state.root === state.selectedItem)
        }
    }
}
