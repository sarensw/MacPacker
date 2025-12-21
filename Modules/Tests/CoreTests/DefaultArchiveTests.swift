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
        let controller = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelectorSwc())
        let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
        
        let url = folderURL.appendingPathComponent("defaultArchive.\(ext)")
        
        try await controller.openAsync(url: url)
        print("")
        
        #expect(controller.type?.id == id)
        #expect(controller.entries.count == 1)
        #expect(controller.root === controller.selectedItem)
    }
    
    @Test("Test all defaultArchives on 7zip", arguments: [
        // ext, id, folder entries
        ("7z", "7zip", 4, 2),
        ("arj", "arj", 3, 2),
        ("ar", "ar", 3, 3), // `ar` archives do not store folders, only folder paths
        ("cab", "cab", 3, 2),
        ("cpio", "cpio", 4, 2),
        ("lzh", "lha", 3, 2),
        ("rar", "rar", 4, 2),
        ("tar", "tar", 4, 2),
        ("xar", "xar", 5, 3), // additional `[TOC].xml`
        ("zip", "zip", 4, 2),
        // installers
        ("rpm", "rpm", 1, 1),
        // disk images
        ("dmg", "dmg", 4, 2),
        ("fat", "fat", 4, 2),
        ("iso", "iso", 4, 2),
        ("qcow2", "qcow2", 4, 2),
        ("squashfs", "squashfs", 4, 2),
        ("vdi", "vdi", 4, 2),
        ("vhd", "vhd", 4, 2),
        ("vhdx", "vhdx", 4, 2),
        ("vmdk", "vmdk", 4, 2),
        // compounds
        ("tar.bz2", "tar", 4, 2),
        ("tar.gz", "tar", 4, 2),
        ("tar.xz", "tar", 4, 2),
        ("tar.Z", "tar", 4, 2),
        // comounds with one ending
        ("tbz2", "tar", 4, 2),
        ("tgz", "tar", 4, 2),
        ("txz", "tar", 4, 2),
        ("taz", "tar", 4, 2)
    ])
    func testAll7zipEngine(arg: (String, String, Int, Int)) async throws {
        let ext = arg.0
        let id = arg.1
        let entries = arg.2
        let rootChildren = arg.3
        let controller = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
        let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
        
        let url = folderURL.appendingPathComponent("defaultArchive.\(ext)")
        
        try await controller.openAsync(url: url)
        print("")
        
        #expect(controller.type?.id == id)
        #expect(controller.entries.count == entries)
        #expect(controller.root?.children?.count == rootChildren)
        #expect(controller.root === controller.selectedItem)
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
        let controller = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelectorXad())
        let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
        
        let url = folderURL.appendingPathComponent("defaultArchive.\(ext)")
        
        try await controller.openAsync(url: url)
        print("")
        
        #expect(controller.type?.id == id)
        #expect(controller.entries.count == (folderEntries ? 4 : 3))
        #expect(controller.root?.children?.count == 2)
        #expect(controller.root === controller.selectedItem)
    }
}
