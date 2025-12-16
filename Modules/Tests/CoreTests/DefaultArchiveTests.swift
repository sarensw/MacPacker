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
        ("7z", "7zip", true),
        ("arj", "arj", false),
        ("cab", "cab", false),
        ("cpio", "cpio", true),
        ("lzh", "lha", false),
        ("rar", "rar", true),
        ("tar", "tar", true),
        ("zip", "zip", true),
        // disk images
        ("dmg", "dmg", true),
        ("iso", "iso", true),
        ("qcow2", "qcow2", true),
        ("squashfs", "squashfs", true),
        ("vdi", "vdi", true),
        ("vhd", "vhd", true),
        ("vhdx", "vhdx", true),
        ("vmdk", "vmdk", true),
        // compounds
        ("tar.bz2", "tar", true),
        ("tar.gz", "tar", true),
        ("tar.xz", "tar", true),
        ("tar.Z", "tar", true),
        // comounds with one ending
        ("tbz2", "tar", true),
        ("tgz", "tar", true),
        ("txz", "tar", true),
        ("taz", "tar", true)
    ])
    func testAll7zipEngine(arg: (String, String, Bool)) async throws {
        let ext = arg.0
        let id = arg.1
        let folderEntries = arg.2
        let controller = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
        let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
        
        let url = folderURL.appendingPathComponent("defaultArchive.\(ext)")
        
        try await controller.openAsync(url: url)
        print("")
        
        #expect(controller.type?.id == id)
        #expect(controller.entries.count == (folderEntries ? 4 : 3))
        #expect(controller.root?.children?.count == 2)
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
    
    @Test("Test rpm defaultArchive on 7zip")
    func testRpm7zipEngine() async throws {
        let controller = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
        let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
        
        let url = folderURL.appendingPathComponent("defaultArchive.\("rpm")")
        
        try await controller.openAsync(url: url)
        print("")
        
        #expect(controller.type?.id == "rpm")
        #expect(controller.entries.count == 1)
        #expect(controller.root?.children?.count == 1)
        #expect(controller.root === controller.selectedItem)
    }
    
    /// `ar` archives do not store folders, only folder paths
    @Test("Test ar defaultArchive on 7zip")
    func testAr7zipEngine() async throws {
        let controller = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
        let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
        
        let url = folderURL.appendingPathComponent("defaultArchive.\("ar")")
        
        try await controller.openAsync(url: url)
        print("")
        
        #expect(controller.type?.id == "ar")
        #expect(controller.entries.count == 3)
        #expect(controller.root?.children?.count == 3)
        #expect(controller.root === controller.selectedItem)
    }
}
