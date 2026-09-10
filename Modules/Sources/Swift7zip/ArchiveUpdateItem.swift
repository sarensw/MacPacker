import Foundation

/// Describes a change to apply when creating or updating an archive.
///
/// Items represent a **diff** against the source archive:
/// - All source entries are kept by default.
/// - Use ``remove(sourceIndex:)`` to drop entries.
/// - Use ``move(sourceIndex:newPath:)`` to rename/relocate entries.
/// - Use the `add` variants to insert new entries.
///
/// When creating a new archive (no source), only `add` items are valid.
/// An empty array means "no changes" — the output is identical to the source.
public enum ArchiveUpdateItem: Sendable {
    /// Remove an existing entry from the archive.
    /// - Parameter sourceIndex: Index of the entry to remove.
    case remove(sourceIndex: UInt32)

    /// Keep the data from an existing entry but change its archive path.
    /// - Parameters:
    ///   - sourceIndex: Index of the entry in the source archive.
    ///   - newPath: New path within the output archive.
    case move(sourceIndex: UInt32, newPath: String)

    /// Add a new file entry from a file on disk.
    /// - Parameters:
    ///   - archivePath: Path within the output archive.
    ///   - diskPath: URL of the file on disk to read data from.
    ///   - modificationDate: Optional modification date override. If `nil`,
    ///     the file's actual modification date is used.
    ///   - posixPermissions: Optional POSIX permission bits override.
    case addFile(
        archivePath: String,
        diskPath: URL,
        modificationDate: Date? = nil,
        posixPermissions: UInt16? = nil
    )

    /// Add a new entry from in-memory data.
    /// - Parameters:
    ///   - archivePath: Path within the output archive.
    ///   - data: Raw bytes for the entry content.
    ///   - modificationDate: Optional modification date.
    ///   - posixPermissions: Optional POSIX permission bits.
    case addData(
        archivePath: String,
        data: Data,
        modificationDate: Date? = nil,
        posixPermissions: UInt16? = nil
    )

    /// Add an empty directory entry.
    /// - Parameters:
    ///   - archivePath: Directory path within the output archive.
    ///   - diskPath: URL of the folder on disk this entry stands for, when there
    ///     is one. Nothing is read from it — the entry is empty either way — but
    ///     a folder carries macOS metadata of its own, and a custom folder icon
    ///     lives there rather than on the `Icon\r` file inside it. Without this
    ///     the icon cannot come back. `nil` for a directory that exists only in
    ///     the archive.
    ///   - modificationDate: Optional modification date.
    ///   - posixPermissions: Optional POSIX permission bits.
    case addDirectory(
        archivePath: String,
        diskPath: URL? = nil,
        modificationDate: Date? = nil,
        posixPermissions: UInt16? = nil
    )
}
