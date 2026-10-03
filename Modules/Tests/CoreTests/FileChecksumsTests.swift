//
//  FileChecksumsTests.swift
//  Modules
//

import Foundation
import Testing
@testable import Core

extension AllCoreTests {
    struct FileChecksumsTests {
        @Test("A file is read once for CRC-32, MD5, SHA-1 and SHA-256")
        func knownValues() async throws {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let file = folder.appendingPathComponent("abc.txt")
            try Data("abc".utf8).write(to: file)

            let checksums = try await FileChecksumCalculator.calculate(file)
            #expect(checksums.crc32 == "352441c2")
            #expect(checksums.md5 == "900150983cd24fb0d6963f7d28e17f72")
            #expect(checksums.sha1 == "a9993e364706816aba3e25717850c26c9cd0d89d")
            #expect(checksums.sha256 == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        }

        @Test("An empty file has the standard checksums")
        func emptyFile() async throws {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try Data().write(to: file)
            defer { try? FileManager.default.removeItem(at: file) }

            let checksums = try await FileChecksumCalculator.calculate(file)
            #expect(checksums.crc32 == "00000000")
            #expect(checksums.md5 == "d41d8cd98f00b204e9800998ecf8427e")
            #expect(checksums.sha1 == "da39a3ee5e6b4b0d3255bfef95601890afd80709")
            #expect(checksums.sha256 == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        }

        @Test("All hashes remain correct across a read-chunk boundary")
        func chunkBoundary() async throws {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try Data(repeating: 0x61, count: 1_048_577).write(to: file)
            defer { try? FileManager.default.removeItem(at: file) }

            let checksums = try await FileChecksumCalculator.calculate(file)
            #expect(checksums.crc32 == "566b6305")
            #expect(checksums.md5 == "6f0555ac53cecbf068d354c08863805a")
            #expect(checksums.sha1 == "7620f339d6b8cd5fa1bc597f291bf713579b9672")
            #expect(checksums.sha256 == "4a3f0c0c213adea174f9a3d4c13177315b588bdb2e9c1012d3d0bf0453ca0f6a")
        }

        @Test("Clipboard verification accepts labelled and sha256sum text")
        func expectedFromClipboard() async throws {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try Data("abc".utf8).write(to: file)
            defer { try? FileManager.default.removeItem(at: file) }
            let checksums = try await FileChecksumCalculator.calculate(file)

            let sha = try #require(ChecksumVerifier.expected(from: "SHA-256: \(checksums.sha256.uppercased())  abc.txt"))
            #expect(sha.algorithm == .sha256)
            #expect(sha.matches(checksums))
            let crc = try #require(ChecksumVerifier.expected(from: "CRC-32 = 352441C2"))
            #expect(crc.algorithm == .crc32)
            #expect(crc.matches(checksums))
            #expect(!ExpectedChecksum(algorithm: .sha256, hex: String(repeating: "0", count: 64)).matches(checksums))
        }

        @Test("A pasted value with no checksum or several checksums is rejected")
        func ambiguousClipboard() {
            #expect(ChecksumVerifier.expected(from: "No checksum copied") == nil)
            #expect(ChecksumVerifier.expected(from: "12345678  abcdef12") == nil)
            #expect(ChecksumVerifier.expected(from: String(repeating: "a", count: 65)) == nil)
        }

        @Test("A missing file reports an error")
        func missingFile() async {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            await #expect(throws: (any Error).self) {
                try await FileChecksumCalculator.calculate(file)
            }
        }
    }
}
