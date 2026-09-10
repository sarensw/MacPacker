//
//  MacMetadata.swift
//  Modules
//
//  The macOS metadata that lives outside a file's contents: extended attributes,
//  the resource fork, and the FinderInfo flags that decide whether a file is
//  invisible and whether a folder shows a custom icon.
//
//  Shared, because both halves of the round trip need it. Extraction tests assert
//  this metadata arrives; creation tests seed it and assert it survives.
//

import Foundation
@testable import Core

/// The two engines that can read a zip.
///
/// Extraction tests about what lands on disk run through both. The fixtures are
/// only proven if either reader gets the same result out of them, and the two get
/// there differently: our own bridge folds AppleDouble sidecars back onto their
/// files, while XADMaster — a Mac tool from the start — does its own handling of
/// resource forks and extended attributes. Nothing but a test says whether they
/// agree.
enum ZipReader: String, CaseIterable, Sendable {
    case sevenZip
    case xad

    var engine: any ArchiveEngine {
        switch self {
        case .sevenZip: Archive7ZipEngine()
        case .xad: ArchiveXadEngine()
        }
    }
}

/// Reads one extended attribute, or nil when the file does not carry it.
/// `FileManager` exposes no API for these, and they are what the AppleDouble
/// work is entirely about — including `com.apple.ResourceFork`, which is how
/// macOS stores a resource fork.
func extendedAttribute(_ name: String, at url: URL) -> Data? {
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
func setExtendedAttribute(_ name: String, _ value: Data, at url: URL) {
    let result = value.withUnsafeBytes {
        setxattr(url.path, name, $0.baseAddress, value.count, 0, 0)
    }
    precondition(result == 0, "setxattr \(name) failed on \(url.path)")
}

/// The FinderInfo flags this codebase cares about. They sit in the same place
/// for a file and a folder — a two-byte field at offset 8 of the 32-byte
/// `com.apple.FinderInfo` attribute — even though everything around them differs
/// (a file has a type and creator there, a folder a window rectangle).
enum FinderFlag {
    /// Keeps `Icon\r` out of sight. Without it Finder lists the file as `Icon?`,
    /// rendering the trailing carriage return as a question mark — which is how
    /// issue #216 was reported.
    static let invisible: UInt16 = 0x4000
    /// Set on the folder, not on the icon file. Finder looks for `Icon\r` only
    /// when it finds this, so a folder without it stays generic no matter what
    /// the icon file holds.
    static let hasCustomIcon: UInt16 = 0x0400
}

/// The 32 bytes of a `com.apple.FinderInfo` attribute carrying `flags` and
/// nothing else.
func finderInfo(flags: UInt16) -> Data {
    var bytes = [UInt8](repeating: 0, count: 32)
    bytes[8] = UInt8(flags >> 8)
    bytes[9] = UInt8(flags & 0xFF)
    return Data(bytes)
}

/// The flags out of a `com.apple.FinderInfo` attribute, or nil when the file
/// carries none.
func finderFlags(at url: URL) -> UInt16? {
    guard let info = extendedAttribute("com.apple.FinderInfo", at: url), info.count >= 10
    else { return nil }
    return UInt16(info[8]) << 8 | UInt16(info[9])
}

/// The name macOS gives the hidden file that holds a folder's custom icon. The
/// trailing carriage return is part of the name, and it is the awkward half of
/// every test that touches this: it is legal in a zip entry name, and stock
/// Info-ZIP `unzip` silently drops it.
let customIconFileName = "Icon\r"

/// Builds a folder that shows a custom icon in Finder, which takes three
/// separate pieces of metadata — losing any one of them loses the picture.
///
/// The resource fork here is a stand-in rather than a real `icns`: what the
/// tests assert is that the bytes make the round trip, and made-up bytes prove
/// that as well as a real icon would while staying obvious about what they are.
/// `zip/customicon.zip` carries the genuine article for the extraction side.
@discardableResult
func makeFolderWithCustomIcon(at folder: URL, fork: Data) throws -> URL {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    let icon = folder.appendingPathComponent(customIconFileName)
    try Data().write(to: icon)
    setExtendedAttribute("com.apple.ResourceFork", fork, at: icon)
    setExtendedAttribute("com.apple.FinderInfo", finderInfo(flags: FinderFlag.invisible), at: icon)
    setExtendedAttribute("com.apple.FinderInfo",
                         finderInfo(flags: FinderFlag.hasCustomIcon), at: folder)
    return icon
}
