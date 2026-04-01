//
//  MagicNumberTests.swift
//  Modules
//
//  Created by Stephan Arenswald on 11.03.26.
//

import Foundation
import Testing
@testable import Core

extension AllCoreTests {
    @MainActor struct MagicNumberTests {
        
        @Test("Test magic numbers", arguments: [
            ("7z", "7zip"),
            ("arj", "arj"),
            ("ar", "ar"),
            ("cab", "cab"),
            ("cpio", "cpio"),
            ("lzh", "lha"),
            ("rar", "rar"),
            ("tar", "tar"),
            ("xar", "pkg"), // additional `[TOC].xml`
            ("zip", "zip"),
            // installers
            ("rpm", "rpm"),
            // disk images
            ("dmg", "dmg"),
            ("iso", "iso"),
            ("qcow2", "qcow2"),
            ("vdi", "vdi"),
            ("vhd", "vhd"),
            ("vhdx", "vhdx"),
            ("vmdk", "vmdk")
        ])
        func magicNumber(arg: (String, String)) async throws {
            let ext = arg.0
            let id = arg.1
            let detector = ArchiveTypeDetector(catalog: ArchiveTypeCatalog())
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            
            let url = folderURL.appendingPathComponent("defaultArchive.\(ext)")
            
            let result = detector.detectByMagicNumber(for: url)
            
            #expect(result?.type.id == id)
        }
    }
}
