//
//  FileChecksums.swift
//  Modules
//
//  Checksums of files on disk, independent of archive formats and engines.
//

import CryptoKit
import Foundation
import zlib

public enum ChecksumAlgorithm: String, CaseIterable, Sendable {
    case crc32 = "CRC-32"
    case md5 = "MD5"
    case sha1 = "SHA-1"
    case sha256 = "SHA-256"

    public var hexLength: Int {
        switch self {
        case .crc32: 8
        case .md5: 32
        case .sha1: 40
        case .sha256: 64
        }
    }
}

public struct FileChecksums: Sendable {
    public let crc32: String
    public let md5: String
    public let sha1: String
    public let sha256: String

    public func value(for algorithm: ChecksumAlgorithm) -> String {
        switch algorithm {
        case .crc32: crc32
        case .md5: md5
        case .sha1: sha1
        case .sha256: sha256
        }
    }
}

public struct ExpectedChecksum: Equatable, Sendable {
    public let algorithm: ChecksumAlgorithm
    public let hex: String

    public init(algorithm: ChecksumAlgorithm, hex: String) {
        self.algorithm = algorithm
        self.hex = hex.lowercased()
    }

    public func matches(_ checksums: FileChecksums) -> Bool {
        checksums.value(for: algorithm) == hex
    }
}

public enum ChecksumVerifier {
    /// Accept a bare checksum, or one copied with a label / filename from a
    /// download page or sha256sum file. More than one distinct checksum is
    /// ambiguous, so it is safer to ask the user to copy just one.
    public static func expected(from text: String) -> ExpectedChecksum? {
        let pattern = #"(?<![0-9a-f])(?:[0-9a-f]{64}|[0-9a-f]{40}|[0-9a-f]{32}|[0-9a-f]{8})(?![0-9a-f])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        guard matches.count == 1,
              let matchRange = Range(matches[0].range, in: text) else { return nil }
        let hex = String(text[matchRange])
        guard let algorithm = ChecksumAlgorithm.allCases.first(where: { $0.hexLength == hex.count }) else { return nil }
        return ExpectedChecksum(algorithm: algorithm, hex: hex)
    }
}

public enum FileChecksumCalculator {
    /// One streaming read computes all four values. The read runs on the
    /// caller's executor; callers with a UI should invoke it in a detached task.
    public static func calculate(_ url: URL) async throws -> FileChecksums {
        try await Sandbox.access(url: url) {
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }

            var crc: uLong = 0
            var md5 = Insecure.MD5()
            var sha1 = Insecure.SHA1()
            var sha256 = SHA256()

            while let chunk = try file.read(upToCount: 1_048_576), !chunk.isEmpty {
                try Task.checkCancellation()
                crc = chunk.withUnsafeBytes { bytes in
                    zlib.crc32(crc, bytes.bindMemory(to: Bytef.self).baseAddress, uInt(chunk.count))
                }
                md5.update(data: chunk)
                sha1.update(data: chunk)
                sha256.update(data: chunk)
            }

            return FileChecksums(
                crc32: String(format: "%08x", UInt32(crc)),
                md5: md5.finalize().map { String(format: "%02x", $0) }.joined(),
                sha1: sha1.finalize().map { String(format: "%02x", $0) }.joined(),
                sha256: sha256.finalize().map { String(format: "%02x", $0) }.joined()
            )
        }
    }
}
