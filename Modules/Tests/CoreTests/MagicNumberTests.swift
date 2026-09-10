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

        // MARK: - ZIP magic-bytes coverage (EOCD vs spanned-marker collision)
        //
        // A normal ZIP begins with the local-file-header signature `50 4B 03 04`,
        // but an EMPTY zip is just a lone 22-byte End-of-Central-Directory record
        // (`50 4B 05 06` + 18 zero bytes). That same `50 4B 05 06` signature is
        // also the zip-spanned split marker in Catalog.json — these tests prove the
        // two uses do not collide: an empty EOCD is matched as plain `zip`, while a
        // spanned terminal volume (EOCD with a non-zero disk field) still wins the
        // spanned classification. Each case uses in-memory bytes + a temp file
        // (same shape as the fixture-less EdgeCaseTests), since the real
        // `empty.zip` / spanned fixtures live in the MacPacker-TestArchives
        // submodule (a maintainer follow-up to add there).

        private func writeTemp(_ bytes: [UInt8], named name: String) -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            FileManager.default.createFile(atPath: url.path, contents: Data(bytes))
            return url
        }

        /// A 22-byte End-of-Central-Directory record (a lone-EOCD / empty ZIP).
        /// `diskNumber` is the 2-byte field at offset 4 — the field the
        /// zip-spanned marker tests for `nonzero`. 0 = a real empty ZIP;
        /// >0 emulates a spanned terminal volume.
        private func eocd(diskNumber: UInt16 = 0) -> [UInt8] {
            var b = [UInt8](repeating: 0x00, count: 22)
            b[0] = 0x50; b[1] = 0x4B; b[2] = 0x05; b[3] = 0x06   // EOCD signature
            b[4] = UInt8(diskNumber & 0xFF)                       // number of this disk (LE)
            b[5] = UInt8((diskNumber >> 8) & 0xFF)
            return b
        }

        @Test func magicNumberNormalZipByBytes() {
            // Local-file-header signature → matched as plain `zip` by magic.
            let detector = ArchiveTypeDetector(catalog: ArchiveTypeCatalog())
            let normalZip = [0x50, 0x4B, 0x03, 0x04] + [UInt8](repeating: 0x00, count: 28)
            let url = writeTemp(normalZip, named: "normal_\(UUID().uuidString).bin")
            defer { try? FileManager.default.removeItem(at: url) }

            let result = detector.detectByMagicNumber(for: url)

            #expect(result?.type.id == "zip")
            #expect(result?.source == .magic)
        }

        @Test func magicNumberEmptyZip() {
            // A lone 22-byte EOCD (entry count = 0) is an empty ZIP — detected as
            // `zip` from the `50 4B 05 06` magic, not left unidentified.
            let detector = ArchiveTypeDetector(catalog: ArchiveTypeCatalog())
            let url = writeTemp(eocd(), named: "empty_\(UUID().uuidString).bin")
            defer { try? FileManager.default.removeItem(at: url) }

            let result = detector.detectByMagicNumber(for: url)

            #expect(result?.type.id == "zip")
            #expect(result?.source == .magic)
        }

        @Test func emptyZipEocdIsNotFlaggedAsSpanned() {
            // The empty EOCD shares `50 4B 05 06` with the zip-spanned marker, yet
            // its disk field is 0 — so it must NOT be classified as a split.
            let detector = ArchiveTypeDetector(catalog: ArchiveTypeCatalog())
            let url = writeTemp(eocd(), named: "empty_\(UUID().uuidString).bin")
            defer { try? FileManager.default.removeItem(at: url) }

            let result = detector.detect(for: url)

            #expect(result?.type.id == "zip")
            #expect(result?.source == .magic)
            #expect(result?.split == nil, "an empty ZIP (disk field 0) must not look like a spanned volume")
        }

        @Test func spannedZipEocdIsNotSwallowedByPlainZipMagic() {
            // An EOCD with a non-zero disk field is the terminal volume of a
            // spanned set. Adding `50 4B 05 06` to zip's magic must not make the
            // plain-zip match swallow it — the detector reclassifies it as spanned.
            let detector = ArchiveTypeDetector(catalog: ArchiveTypeCatalog())
            let url = writeTemp(eocd(diskNumber: 2), named: "spanned_\(UUID().uuidString).bin")
            defer { try? FileManager.default.removeItem(at: url) }

            let result = detector.detect(for: url)

            #expect(result?.type.id == "zip")
            #expect(result?.split?.scheme == "spanned", "a non-zero disk field must keep the spanned classification")
        }
    }
}
