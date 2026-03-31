import Foundation

/// Metadata for a single entry within an archive.
/// Value type -- safe to pass across concurrency boundaries.
public struct SevenZipEntry: Sendable, Hashable {
    /// Zero-based index of this entry in the archive.
    public let index: UInt32
    /// Relative path of the entry within the archive.
    public let path: String
    /// Filename only (last path component), without directory separators.
    public let name: String
    /// Index of the parent entry, or `nil` if this is a root-level entry.
    /// Populated from the archive's native tree structure for tree-based formats
    /// (disk images like NTFS, HFS+, Ext, APFS). For non-tree formats this is `nil`.
    public let parentIndex: UInt32?
    /// Uncompressed size in bytes.
    public let size: UInt64
    /// Compressed size in bytes.
    public let packedSize: UInt64
    /// Whether the entry represents a directory.
    public let isDirectory: Bool
    /// Whether the entry is encrypted.
    public let isEncrypted: Bool
    /// Whether the entry is an alternate data stream (e.g. macOS extended
    /// attributes like `com.apple.provenance`, or NTFS ADS).
    public let isAltStream: Bool
    /// POSIX file-mode permission bits (e.g. `0o755`), or `nil` if the archive format does not store them.
    public let posixPermissions: UInt16?
    /// Last modification date, or `nil` if unknown.
    public let modificationDate: Date?
}
