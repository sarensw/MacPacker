import Foundation
import CSevenZip

/// An open 7-zip archive.
public class SevenZipArchive {

    private let handle: BridgeHandle
    /// The URL of the archive file.
    public let url: URL
    private var hasPassword = false

    // MARK: - Lifecycle

    /// Opens the archive at the given file URL.
    /// - Parameter url: A file URL pointing to an archive.
    /// - Throws: ``SevenZipError/openFailed(_:)`` if the file cannot
    ///   be opened or no supported format is detected.
    public init(url: URL) throws {
        self.url = url
        self.handle = try Self.openHandle(at: url)
    }

    /// Opens the C bridge handle at the given URL.
    private static func openHandle(at url: URL) throws -> BridgeHandle {
        var errorPtr: UnsafeMutablePointer<CChar>?
        guard let ref = sz_open(url.path, &errorPtr) else {
            let msg = errorPtr.map { ptr -> String in
                let str = String(cString: ptr)
                free(ptr)
                return str
            } ?? "Unknown error"
            throw SevenZipError.openFailed(msg)
        }
        return BridgeHandle(ref: ref)
    }

    // MARK: - Inspection

    /// Version string of the embedded 7-zip bridge.
    public static var libraryVersion: String {
        String(cString: sz_version())
    }

    /// Whether the archive natively provides parent-child tree structure.
    ///
    /// When `true`, each ``SevenZipEntry/parentIndex`` is populated from the
    /// archive's native tree (disk images like NTFS, HFS+, Ext, APFS).
    /// When `false`, entries only have path strings and ``SevenZipEntry/parentIndex``
    /// is `nil`.
    public var isTree: Bool {
        sz_is_tree(handle.ref)
    }

    /// All entries in the archive.
    ///
    /// Alternate data streams (macOS extended attributes, NTFS ADS)
    /// are excluded — ``sz_get_entry`` returns `false` for them.
    public var entries: [SevenZipEntry] {
        get throws {
            let count = sz_entry_count(handle.ref)
            guard count >= 0 else {
                throw SevenZipError.openFailed(
                    "Could not read entry count")
            }
            return (0..<UInt32(count)).compactMap { index in
                var raw = SZEntry()
                guard sz_get_entry(handle.ref, index, &raw) else {
                    return nil
                }
                return SevenZipEntry(bridgeEntry: raw)
            }
        }
    }

    // MARK: - Password

    /// Sets the password used for extracting encrypted entries.
    /// - Parameter password: The password string.
    public func setPassword(_ password: String) {
        sz_set_password(handle.ref, password)
        hasPassword = true
    }

    // MARK: - Extraction

    /// Extracts a single entry to the given directory.
    /// - Parameters:
    ///   - index: The index of the entry to extract.
    ///   - destination: A file URL for the target directory
    ///     (must already exist).
    /// - Returns: A dictionary mapping each entry index to its
    ///   extracted file URL on disk.
    /// - Throws: ``SevenZipError/passwordMissing`` if the entry is
    ///   encrypted and no password was set,
    ///   ``SevenZipError/extractionFailed(_:)`` on failure.
    @discardableResult
    public func extract(
        index: UInt32,
        to destination: URL
    ) throws -> [UInt32: URL] {
        var raw = SZEntry()
        guard sz_get_entry(handle.ref, index, &raw) else {
            throw SevenZipError.entryAccessFailed(index)
        }
        let entry = SevenZipEntry(bridgeEntry: raw)
        if entry.isEncrypted && !hasPassword {
            throw SevenZipError.passwordMissing
        }
        var errorPtr: UnsafeMutablePointer<CChar>?
        let result = sz_extract_entry(
            handle.ref, index,
            destination.path, &errorPtr)
        if result != 0 {
            let msg = errorPtr.map { ptr -> String in
                let str = String(cString: ptr)
                free(ptr)
                return str
            } ?? "Unknown error"
            throw SevenZipError.extractionFailed(msg)
        }
        return [index: destination.appendingPathComponent(entry.path)]
    }

    /// Extracts multiple entries by index to the given directory.
    ///
    /// This is more efficient than calling ``extract(index:to:)`` in a loop
    /// because 7-zip processes all indices in a single pass over the archive.
    /// - Parameters:
    ///   - indices: The indices of entries to extract. Must be sorted
    ///     in ascending order.
    ///   - destination: A file URL for the target directory
    ///     (must already exist).
    /// - Returns: A dictionary mapping each entry index to its
    ///   extracted file URL on disk.
    /// - Throws: ``SevenZipError/passwordMissing`` if any entry is
    ///   encrypted and no password was set,
    ///   ``SevenZipError/extractionFailed(_:)`` on failure.
    @discardableResult
    public func extract(
        indices: [UInt32],
        to destination: URL
    ) throws -> [UInt32: URL] {
        guard !indices.isEmpty else { return [:] }
        var indexPaths: [(UInt32, String)] = []
        for index in indices {
            var raw = SZEntry()
            guard sz_get_entry(handle.ref, index, &raw) else {
                throw SevenZipError.entryAccessFailed(index)
            }
            if !hasPassword && raw.is_encrypted {
                throw SevenZipError.passwordMissing
            }
            indexPaths.append((index, raw.path.map { String(cString: $0) } ?? ""))
        }
        var errorPtr: UnsafeMutablePointer<CChar>?
        let result = indices.withUnsafeBufferPointer { buf in
            sz_extract_entries(
                handle.ref, buf.baseAddress,
                UInt32(buf.count),
                destination.path, &errorPtr)
        }
        if result != 0 {
            let msg = errorPtr.map { ptr -> String in
                let str = String(cString: ptr)
                free(ptr)
                return str
            } ?? "Unknown error"
            throw SevenZipError.extractionFailed(msg)
        }
        var result2: [UInt32: URL] = [:]
        for (idx, path) in indexPaths {
            result2[idx] = destination.appendingPathComponent(path)
        }
        return result2
    }

    /// Extracts all entries to the given directory.
    /// - Parameter destination: A file URL for the target directory
    ///   (must already exist).
    /// - Returns: A dictionary mapping each entry index to its
    ///   extracted file URL on disk.
    /// - Throws: ``SevenZipError/passwordMissing`` if any entry is
    ///   encrypted and no password was set,
    ///   ``SevenZipError/extractionFailed(_:)`` on failure.
    @discardableResult
    public func extractAll(to destination: URL) throws -> [UInt32: URL] {
        let allEntries = try entries
        if !hasPassword && allEntries.contains(where: \.isEncrypted) {
            throw SevenZipError.passwordMissing
        }
        var errorPtr: UnsafeMutablePointer<CChar>?
        let result = sz_extract_all(
            handle.ref, destination.path, &errorPtr)
        if result != 0 {
            let msg = errorPtr.map { ptr -> String in
                let str = String(cString: ptr)
                free(ptr)
                return str
            } ?? "Unknown error"
            throw SevenZipError.extractionFailed(msg)
        }
        var result2: [UInt32: URL] = [:]
        for entry in allEntries {
            result2[entry.index] = destination.appendingPathComponent(entry.path)
        }
        return result2
    }
}

// MARK: - Internal Conversion

extension SevenZipEntry {
    init(bridgeEntry raw: SZEntry) {
        self.index = raw.index
        self.path = raw.path.map { String(cString: $0) } ?? ""
        self.name = raw.name.map { String(cString: $0) } ?? ""
        self.parentIndex = raw.parent_index >= 0
            ? UInt32(raw.parent_index)
            : nil
        self.size = raw.size
        self.packedSize = raw.packed_size
        self.isDirectory = raw.is_directory
        self.isEncrypted = raw.is_encrypted
        self.isAltStream = raw.is_alt_stream
        self.posixPermissions = raw.posix_permissions != 0
            ? UInt16(raw.posix_permissions & 0o7777)
            : nil
        self.modificationDate = raw.mtime >= 0
            ? Date(timeIntervalSince1970: TimeInterval(raw.mtime))
            : nil
    }
}
