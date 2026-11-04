import Foundation
import CSevenZip

/// An open 7-zip archive.
public class SevenZipArchive {

    let handle: BridgeHandle
    /// The URL of the archive file.
    public let url: URL
    /// Whether a password has been supplied for this archive.
    public private(set) var hasPassword = false

    // MARK: - Lifecycle

    /// Opens the archive at the given file URL.
    /// - Parameters:
    ///   - url: A file URL pointing to an archive.
    ///   - password: Password for formats that encrypt their header (7z
    ///     `-mhe=on`, RAR `-hp`), which cannot even be listed without one.
    ///     Also pre-sets the extraction password.
    /// - Throws: ``SevenZipError/passwordMissing`` when the header is encrypted
    ///   and no password was given, ``SevenZipError/passwordWrong`` when the
    ///   given one did not decrypt it, ``SevenZipError/openFailed(_:)`` if the
    ///   file cannot be opened or no supported format is detected.
    public init(url: URL, password: String? = nil) throws {
        self.url = url
        self.handle = try Self.openHandle(at: url, password: password)
        self.hasPassword = password != nil
    }

    /// Opens the C bridge handle at the given URL.
    private static func openHandle(at url: URL, password: String?) throws -> BridgeHandle {
        var errorPtr: UnsafeMutablePointer<CChar>?
        var needsPassword = false
        guard let ref = sz_open(url.path, password, &needsPassword, &errorPtr) else {
            let msg = errorPtr.map { ptr -> String in
                let str = String(cString: ptr)
                free(ptr)
                return str
            } ?? "Unknown error"
            if needsPassword {
                throw password == nil
                    ? SevenZipError.passwordMissing
                    : SevenZipError.passwordWrong
            }
            throw SevenZipError.openFailed(msg)
        }
        return BridgeHandle(ref: ref)
    }

    // MARK: - Inspection

    /// Version of the embedded 7-Zip library, e.g. `26.06`.
    ///
    /// Read from the vendored sources at compile time, so it follows the
    /// `Sources/CSevenZip/vendor/7zip` submodule automatically.
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

    /// The format 7-Zip opened the archive as, by the name of the handler that
    /// did — `7z`, `zip`, `tar`, `Rar5` — or `nil` when it has none. It is what
    /// the archive is, whatever its file is called. For a set of volumes it is
    /// the format of the archive they make up, not `Split`.
    public var formatName: String? {
        sz_format_name(handle.ref).map { String(cString: $0) }
    }

    /// How the entry at `index` is compressed, as 7-Zip names it — `Deflate`,
    /// `LZMA2:22`, `PPMD:o6:mem24`, `Copy`, `Store` — or `nil` when the archive
    /// does not say.
    public func method(ofEntryAt index: UInt32) -> String? {
        sz_entry_method(handle.ref, index).map { String(cString: $0) }
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

    // MARK: - Names

    /// The names as 7-Zip read them and the bytes the archive stores them in, by
    /// entry, when one of them can be in a code page, and nothing otherwise. Every
    /// entry is in there that is not plain ASCII, the hidden
    /// sidecars included, unless it declares UTF-8 itself and is: the archive does
    /// not say what the others are in, so whoever knows has to say for all of
    /// them. A flag on bytes that are not UTF-8 says nothing, as `bsdtar` sets it
    /// whenever the locale is UTF-8, whatever the name is in.
    public var storedNames: [(index: UInt32, path: String, bytes: Data)] {
        guard sz_has_undecoded_paths(handle.ref) || canHideCodePages else { return [] }
        return (0..<UInt32(Swift.max(0, sz_entry_count(handle.ref)))).compactMap { index in
            guard let stored = sz_entry_path(handle.ref, index) else { return nil }
            let path = String(cString: stored)
            let bytes = Self.storedBytes(of: path)
            guard bytes.contains(where: { $0 >= 0x80 }) else { return nil }
            return sz_entry_declares_utf8(handle.ref, index) && String(data: bytes, encoding: .utf8) != nil
                ? nil : (index, path, bytes)
        }
    }

    /// Whether names 7-Zip read as UTF-8 can be in a code page all the same, as
    /// `图片` in GBK happens to be valid UTF-8. A 7z or a RAR5 stores Unicode, and
    /// 7-Zip does not say which is which: these two are where it says of a name.
    // ponytail: zip and tar. In LZH, CAB and the like a code page takes a name that does not read.
    private var canHideCodePages: Bool {
        ["zip", "tar"].contains(formatName ?? "") && sz_has_non_ascii_paths(handle.ref)
    }

    /// Whether a `/` in a stored name can be a 0x5C. The handlers of these formats
    /// take every 0x5C for a path separator (`WinPathToOsPath`), also the second
    /// byte of a character: ソ and 表 in Shift-JIS, 許 in Big5.
    public var slashesWereBackslashes: Bool {
        ["Lzh", "Rar", "Cab"].contains(formatName ?? "")
    }

    /// Undoes what `sz_has_undecoded_paths` describes.
    private static func storedBytes(of path: String) -> Data {
        var bytes = Data()
        for scalar in path.unicodeScalars {
            if (0xEF80...0xEFFF).contains(scalar.value) {
                bytes.append(UInt8(truncatingIfNeeded: scalar.value))
            } else {
                bytes.append(contentsOf: String(scalar).utf8)
            }
        }
        return bytes
    }

    /// Lists and extracts the entry at `index` as `path`, for a name read in the
    /// right code page. The archive stays as it is.
    public func setPath(_ path: String, ofEntryAt index: UInt32) {
        sz_set_entry_path(handle.ref, index, path)
    }

    // MARK: - Password

    /// Sets the password used for extracting encrypted entries.
    /// - Parameter password: The password string.
    public func setPassword(_ password: String) {
        sz_set_password(handle.ref, password)
        hasPassword = true
    }

    // MARK: - Extraction

    /// Maps a bridge `SZ_EXTRACT_*` code to a typed error, consuming
    /// `errorPtr`. Returns normally when the extraction succeeded.
    private static func check(
        _ result: Int32,
        _ errorPtr: UnsafeMutablePointer<CChar>?
    ) throws {
        let message = errorPtr.map { ptr -> String in
            let str = String(cString: ptr)
            free(ptr)
            return str
        } ?? "Unknown error"

        switch result {
        case SZ_EXTRACT_OK: return
        case SZ_EXTRACT_ABORTED: throw SevenZipError.cancelled
        case SZ_EXTRACT_WRONG_PASSWORD: throw SevenZipError.passwordWrong
        default: throw SevenZipError.extractionFailed(message)
        }
    }

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
        try Self.check(result, errorPtr)
        return [index: Self.extractedURL(of: entry.path, in: destination)]
    }

    private static func extractedURL(of path: String, in destination: URL) -> URL {
        destination.appendingPathComponent(extractedPath(of: path))
    }

    /// Where an extraction writes `path`, below its destination: the bridge drops
    /// every empty, "." and ".." part, so that nothing lands outside of it.
    static func extractedPath(of path: String) -> String {
        path.split(separator: "/").filter { $0 != "." && $0 != ".." }.joined(separator: "/")
    }

    /// Byte progress during extraction, as reported by 7-Zip itself.
    /// `completed` and `total` share the handler's processed-bytes unit.
    /// Return `false` to abort the extraction. Called on the extraction
    /// thread.
    public typealias ProgressHandler = (_ completed: UInt64, _ total: UInt64) -> Bool

    /// Box that carries the progress closure through the C callback.
    private final class ProgressBox {
        let handler: ProgressHandler
        init(_ handler: @escaping ProgressHandler) { self.handler = handler }
    }

    private static let progressThunk: sz_progress_callback = { completed, total, context in
        guard let context else { return true }
        let box = Unmanaged<ProgressBox>.fromOpaque(context).takeUnretainedValue()
        return box.handler(completed, total)
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
    ///   - progress: Optional byte-progress callback; return `false` to abort.
    /// - Returns: A dictionary mapping each entry index to its
    ///   extracted file URL on disk.
    /// - Throws: ``SevenZipError/passwordMissing`` if any entry is
    ///   encrypted and no password was set, ``SevenZipError/cancelled``
    ///   when the progress callback aborted,
    ///   ``SevenZipError/extractionFailed(_:)`` on failure.
    @discardableResult
    public func extract(
        indices: [UInt32],
        to destination: URL,
        progress: ProgressHandler? = nil
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

        let box = progress.map(ProgressBox.init)
        var errorPtr: UnsafeMutablePointer<CChar>?
        let result = withExtendedLifetime(box) {
            indices.withUnsafeBufferPointer { buf in
                sz_extract_entries(
                    handle.ref, buf.baseAddress,
                    UInt32(buf.count),
                    destination.path,
                    box != nil ? Self.progressThunk : nil,
                    box.map { Unmanaged.passUnretained($0).toOpaque() },
                    &errorPtr)
            }
        }
        try Self.check(result, errorPtr)
        var result2: [UInt32: URL] = [:]
        for (idx, path) in indexPaths {
            result2[idx] = Self.extractedURL(of: path, in: destination)
        }
        return result2
    }

    /// Extracts all entries to the given directory.
    /// - Parameters:
    ///   - destination: A file URL for the target directory
    ///     (must already exist).
    ///   - progress: Optional byte-progress callback; return `false` to abort.
    /// - Returns: A dictionary mapping each entry index to its
    ///   extracted file URL on disk.
    /// - Throws: ``SevenZipError/passwordMissing`` if any entry is
    ///   encrypted and no password was set, ``SevenZipError/cancelled``
    ///   when the progress callback aborted,
    ///   ``SevenZipError/extractionFailed(_:)`` on failure.
    @discardableResult
    public func extractAll(
        to destination: URL,
        progress: ProgressHandler? = nil
    ) throws -> [UInt32: URL] {
        let allEntries = try entries
        if !hasPassword && allEntries.contains(where: \.isEncrypted) {
            throw SevenZipError.passwordMissing
        }
        let box = progress.map(ProgressBox.init)
        var errorPtr: UnsafeMutablePointer<CChar>?
        let result = withExtendedLifetime(box) {
            sz_extract_all(
                handle.ref, destination.path,
                box != nil ? Self.progressThunk : nil,
                box.map { Unmanaged.passUnretained($0).toOpaque() },
                &errorPtr)
        }
        try Self.check(result, errorPtr)
        var result2: [UInt32: URL] = [:]
        for entry in allEntries {
            result2[entry.index] = Self.extractedURL(of: entry.path, in: destination)
        }
        return result2
    }

    // MARK: - Testing

    /// Decodes every entry and checks it against its checksum, writing nothing.
    /// - Parameter progress: Optional byte-progress callback; return `false` to abort.
    /// - Returns: the paths of the entries that did not decode or did not match
    ///   their checksum, and whether the archive reports damage of its own — cut
    ///   short, its headers broken — which no entry has to show.
    /// - Throws: ``SevenZipError/passwordMissing`` if any entry is encrypted and
    ///   no password was set, ``SevenZipError/passwordWrong`` when the one set did
    ///   not decrypt them, ``SevenZipError/cancelled`` when the progress callback
    ///   aborted, ``SevenZipError/extractionFailed(_:)`` when the test could not run.
    public func test(
        progress: ProgressHandler? = nil
    ) throws -> (damagedPaths: [String], archiveIsDamaged: Bool) {
        if !hasPassword, try entries.contains(where: \.isEncrypted) {
            throw SevenZipError.passwordMissing
        }
        let box = progress.map(ProgressBox.init)
        var damaged: UnsafeMutablePointer<UInt32>?
        var count: UInt32 = 0
        var archiveIsDamaged = false
        var errorPtr: UnsafeMutablePointer<CChar>?
        let result = withExtendedLifetime(box) {
            sz_test_all(
                handle.ref,
                box != nil ? Self.progressThunk : nil,
                box.map { Unmanaged.passUnretained($0).toOpaque() },
                &damaged, &count, &archiveIsDamaged, &errorPtr)
        }
        defer { free(damaged) }
        if result != SZ_TEST_DAMAGED {
            try Self.check(result, errorPtr)
        }
        let indices = UnsafeBufferPointer(start: damaged, count: Int(count))
        return (indices.map(path(ofEntryAt:)), archiveIsDamaged)
    }

    /// The path the listing shows `index` under, or for an entry it leaves out —
    /// a sidecar, an alternate stream — the one it is stored under.
    private func path(ofEntryAt index: UInt32) -> String {
        var raw = SZEntry()
        if sz_get_entry(handle.ref, index, &raw), let path = raw.path {
            return String(cString: path)
        }
        return sz_entry_path(handle.ref, index).map { String(cString: $0) } ?? ""
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
