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

    /// All entries in the archive.
    public var entries: [SevenZipEntry] {
        get throws {
            let count = sz_entry_count(handle.ref)
            guard count >= 0 else {
                throw SevenZipError.openFailed(
                    "Could not read entry count")
            }
            return try (0..<UInt32(count)).map { index in
                var raw = SZEntry()
                guard sz_get_entry(handle.ref, index, &raw) else {
                    throw SevenZipError.entryAccessFailed(index)
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
    /// - Throws: ``SevenZipError/passwordMissing`` if the entry is
    ///   encrypted and no password was set,
    ///   ``SevenZipError/extractionFailed(_:)`` on failure.
    public func extract(
        index: UInt32,
        to destination: URL
    ) throws {
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
    }

    /// Extracts all entries to the given directory.
    /// - Parameter destination: A file URL for the target directory
    ///   (must already exist).
    /// - Throws: ``SevenZipError/passwordMissing`` if any entry is
    ///   encrypted and no password was set,
    ///   ``SevenZipError/extractionFailed(_:)`` on failure.
    public func extractAll(to destination: URL) throws {
        if !hasPassword {
            let allEntries = try entries
            if allEntries.contains(where: \.isEncrypted) {
                throw SevenZipError.passwordMissing
            }
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
    }
}

// MARK: - Internal Conversion

extension SevenZipEntry {
    init(bridgeEntry raw: SZEntry) {
        self.index = raw.index
        self.path = raw.path.map { String(cString: $0) } ?? ""
        self.size = raw.size
        self.packedSize = raw.packed_size
        self.isDirectory = raw.is_directory
        self.isEncrypted = raw.is_encrypted
        self.posixPermissions = raw.posix_permissions != 0
            ? UInt16(raw.posix_permissions & 0o7777)
            : nil
        self.modificationDate = raw.mtime >= 0
            ? Date(timeIntervalSince1970: TimeInterval(raw.mtime))
            : nil
    }
}
