//
//  DefaultArchiveTests.swift
//  Modules
//
//  Created by Stephan Arenswald on 12.12.25.
//

import Foundation
import Testing
@testable import Core

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
        #expect(state.entries.count == 1)
        #expect(state.root === state.selectedItem)
    }
    
    @Test("Test all defaultArchives on 7zip", arguments: [
        // ext, id, folder entries
        ("7z", "7zip", 5, 2),
        ("arj", "arj", 4, 2),
        ("ar", "ar", 4, 3), // `ar` archives do not store folders, only folder paths
        ("cab", "cab", 4, 2),
        ("cpio", "cpio", 5, 2),
        ("lzh", "lha", 4, 2),
        ("rar", "rar", 5, 2),
        ("tar", "tar", 5, 2),
        ("xar", "xar", 6, 3), // additional `[TOC].xml`
        ("zip", "zip", 5, 2),
        // installers
        ("rpm", "rpm", 2, 1),
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
        ("tar.xz", "tar", 5, 2),
        ("tar.Z", "tar", 5, 2),
        // comounds with one ending
        ("tbz2", "tar", 5, 2),
        ("tgz", "tar", 5, 2),
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
    
    @Test("Test all defaultArchives on xad", arguments: [
        ("zip", "zip", true),
        ("7z", "7zip", true),
        ("tbz2", "tar", true),
        ("tar.bz2", "tar", true),
        ("cab", "cab", false),
        ("cpio", "cpio", true)
    ])
    func testAllXadEngine(arg: (String, String, Bool)) async throws {
        let ext = arg.0
        let id = arg.1
        let folderEntries = arg.2
        let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelectorXad())
        let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
        
        let url = folderURL.appendingPathComponent("defaultArchive.\(ext)")
        
        state.open(url: url)
        try await state.openTask?.value
        
        #expect(state.type?.id == id)
        #expect(state.entries.count == (folderEntries ? 4 : 3))
        #expect(state.root?.children?.count == 2)
        #expect(state.root === state.selectedItem)
    }
}
