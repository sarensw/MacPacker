import Foundation

/// Metadata for a single entry within an archive.
/// Value type -- safe to pass across concurrency boundaries.
public struct SevenZipEntry: Sendable, Hashable {
    /// Zero-based index of this entry in the archive.
    public let index: UInt32
    /// Relative path of the entry within the archive.
    public let path: String
    /// Uncompressed size in bytes.
    public let size: UInt64
    /// Compressed size in bytes.
    public let packedSize: UInt64
    /// Whether the entry represents a directory.
    public let isDirectory: Bool
    /// Whether the entry is encrypted.
    public let isEncrypted: Bool
    /// POSIX file-mode permission bits (e.g. `0o755`), or `nil` if the archive format does not store them.
    public let posixPermissions: UInt16?
    /// Last modification date, or `nil` if unknown.
    public let modificationDate: Date?
}
