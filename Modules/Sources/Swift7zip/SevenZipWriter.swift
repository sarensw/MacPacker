import Foundation
import CSevenZip

extension SevenZipArchive {

    /// Creates or updates an archive by applying a diff.
    ///
    /// When editing (`source` is non-nil), all source entries are kept
    /// by default. Items in `items` describe **changes** to apply:
    /// removals, renames, and additions. An empty `items` array means
    /// "no changes" — the output is identical to the source.
    ///
    /// When creating a new archive (`source` is `nil`), only `add`
    /// variants are valid (there are no source entries to remove or move).
    ///
    /// If `source` and `destination` are the same URL, the archive
    /// is written to a temporary file and atomically replaced.
    ///
    /// - Parameters:
    ///   - source: URL of the source archive, or `nil` to create new.
    ///   - destination: URL where the output archive will be written.
    ///   - items: The diff to apply (removals, moves, additions).
    ///   - options: Compression options. Defaults to 7z format, level 5.
    /// - Throws: ``SevenZipError/writeFailed(_:)`` on failure.
    /// Byte progress during an archive write, as reported by 7-Zip.
    /// `completed`/`total` share the handler's processed-bytes unit. Return
    /// `false` to abort the write. Called on the writing thread.
    public typealias WriteProgressHandler = (_ completed: UInt64, _ total: UInt64) -> Bool

    public static func writeArchive(
        source: URL? = nil,
        destination: URL,
        items: [ArchiveUpdateItem],
        options: SevenZipCompressionOptions = .init(),
        progress: WriteProgressHandler? = nil
    ) throws {
        let inPlace = source != nil
            && source!.standardizedFileURL == destination.standardizedFileURL
        let actualDest: URL
        if inPlace {
            // Write to the system temp directory (always writable, even
            // in a sandboxed app) rather than next to the source file.
            actualDest = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    UUID().uuidString + "." + destination.pathExtension)
        } else {
            actualDest = destination
        }

        // Resolve the diff into a full item list for the C bridge.
        var resolved = try resolveDiff(source: source, items: items)

        // Everything macOS keeps outside a file's contents travels as an extra
        // entry per file, packed into a scratch directory that lives exactly as
        // long as this write does.
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        // Not `try?`: one failed directory would silently turn the whole of the
        // above into a no-op, and the archive would come out stripped.
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        resolved.append(contentsOf: try metadataSidecars(for: resolved, scratch: scratch))

        try performUpdate(
            source: source,
            destination: actualDest,
            resolvedItems: resolved,
            options: options,
            progress: progress
        )

        if inPlace {
            let fm = FileManager.default
            do {
                _ = try fm.replaceItemAt(destination, withItemAt: actualDest)
            } catch {
                try? fm.removeItem(at: actualDest)
                throw error
            }
        }
    }

    // MARK: - Diff Resolution

    /// A resolved item ready for the C bridge.
    private enum ResolvedItem {
        case keep(sourceIndex: UInt32)
        case move(sourceIndex: UInt32, newPath: String)
        case addFile(archivePath: String, diskPath: URL,
                     modificationDate: Date?, posixPermissions: UInt16?)
        case addData(archivePath: String, data: Data,
                     modificationDate: Date?, posixPermissions: UInt16?)
        case addDirectory(archivePath: String, diskPath: URL?,
                          modificationDate: Date?, posixPermissions: UInt16?)
    }

    /// Resolves a user-facing diff into the full list the C bridge expects.
    /// All source entries are kept unless explicitly removed or moved.
    private static func resolveDiff(
        source: URL?,
        items: [ArchiveUpdateItem]
    ) throws -> [ResolvedItem] {
        // Collect removals and moves from the diff.
        var removedIndices: Set<UInt32> = []
        var movedIndices: [UInt32: String] = [:]
        var additions: [ResolvedItem] = []

        for item in items {
            switch item {
            case .remove(let idx):
                removedIndices.insert(idx)
            case .move(let idx, let newPath):
                movedIndices[idx] = newPath
            case .addFile(let p, let url, let d, let perms):
                additions.append(.addFile(
                    archivePath: p, diskPath: url,
                    modificationDate: d, posixPermissions: perms))
            case .addData(let p, let data, let d, let perms):
                additions.append(.addData(
                    archivePath: p, data: data,
                    modificationDate: d, posixPermissions: perms))
            case .addDirectory(let p, let url, let d, let perms):
                additions.append(.addDirectory(
                    archivePath: p, diskPath: url, modificationDate: d,
                    posixPermissions: perms))
            }
        }

        var result: [ResolvedItem] = []

        // Build keeps/moves from source entries.
        if let source {
            let archive = try SevenZipArchive(url: source)
            let entryCount = sz_entry_count(archive.handle.ref)
            guard entryCount >= 0 else {
                throw SevenZipError.writeFailed(
                    "Could not read entry count from source")
            }
            for i in 0..<UInt32(entryCount) {
                if removedIndices.contains(i) { continue }
                // A sidecar is its file's extended attributes and resource fork,
                // not a file of its own, and it is not in the listing for the user
                // to remove alongside. Dropping the file drops them with it, or the
                // archive keeps metadata describing something it no longer holds —
                // which then shows up as a stray `._name` entry.
                let sidecarTarget = sz_sidecar_target(archive.handle.ref, i)
                if sidecarTarget >= 0 && removedIndices.contains(UInt32(sidecarTarget)) { continue }
                if let newPath = movedIndices[i] {
                    result.append(.move(sourceIndex: i, newPath: newPath))
                } else {
                    result.append(.keep(sourceIndex: i))
                }
            }
        }

        result.append(contentsOf: additions)
        return result
    }

    // MARK: - macOS Metadata

    /// Where the sidecar for `archivePath` goes: `dir/name` becomes
    /// `__MACOSX/dir/._name`.
    ///
    /// The mirror rather than a `._name` beside the file it describes. Both forms
    /// are read back, but an extractor that does not fold them in writes the
    /// sidecar out as an ordinary file — and inside a signed `.app` that extra
    /// file breaks the code-signature seal and macOS calls the app damaged. That
    /// is issue #189 seen from the writing end. `__MACOSX/` keeps every sidecar
    /// outside the bundle, and it is what Finder's "Compress" produces, so it is
    /// also the shape other tools already expect.
    private static func sidecarPath(for archivePath: String) -> String {
        var parts = archivePath.split(separator: "/", omittingEmptySubsequences: true)
        guard let name = parts.popLast() else { return archivePath }
        let directory = parts.joined(separator: "/")
        return directory.isEmpty
            ? "__MACOSX/._\(name)"
            : "__MACOSX/\(directory)/._\(name)"
    }

    /// Extended attributes that describe this Mac rather than the file, and so
    /// have no business in an archive that will be opened on another one.
    ///
    /// `com.apple.quarantine` is the one that matters: it is Gatekeeper's verdict
    /// on where the file came from, and `copyfile` packs it like any other
    /// attribute. Storing it would put the machine's browsing history into every
    /// archive MacPacker writes, and hand the extracting side a verdict the
    /// archive was never entitled to make — the same argument the extraction path
    /// already makes for refusing to apply one.
    ///
    /// The rest are noise that would otherwise earn a sidecar all by themselves.
    /// `com.apple.TextEncoding` in particular is written by Cocoa whenever a text
    /// file is saved, so without this every `.txt` in every archive would carry a
    /// second entry to say it is UTF-8.
    private static let systemOwnedAttributes: Set<String> = [
        "com.apple.quarantine",
        "com.apple.provenance",
        "com.apple.lastuseddate#PS",
        "com.apple.macl",
        "com.apple.TextEncoding",
    ]

    /// A failure in the metadata path, carrying what the C call reported.
    ///
    /// Everything below reports rather than shrugs, because "could not read the
    /// metadata" and "there was no metadata" produce the same archive and mean
    /// opposite things. Treating the first as the second is how a custom folder
    /// icon goes missing with nobody told — which is the bug this whole change
    /// exists to fix, reached from a different direction. Under the sandbox it is
    /// not hypothetical: without a security-scoped grant `listxattr` fails with
    /// EACCES on a folder whose contents are never read.
    private static func metadataError(_ call: String, _ url: URL) -> SevenZipError {
        .writeFailed("\(call) failed for \(url.lastPathComponent): "
                     + String(cString: strerror(errno)))
    }

    /// The names of every extended attribute on `url`.
    private static func attributeNames(of url: URL) throws -> [String] {
        let size = listxattr(url.path, nil, 0, XATTR_NOFOLLOW)
        guard size >= 0 else { throw metadataError("listxattr", url) }
        guard size > 0 else { return [] }

        var buffer = [CChar](repeating: 0, count: size)
        // A shrinking set between the two calls is a race, not an empty one.
        guard listxattr(url.path, &buffer, size, XATTR_NOFOLLOW) == size else {
            throw metadataError("listxattr", url)
        }

        // listxattr returns the names NUL-separated in one buffer.
        return buffer.split(separator: 0).map { String(cString: Array($0) + [0]) }
    }

    /// Serializes what macOS keeps outside a file's contents — resource fork,
    /// extended attributes, and the FinderInfo that carries a custom-icon or
    /// invisible flag — into AppleDouble. Returns the file written.
    ///
    /// `copyfile` with COPYFILE_PACK is the same call `ditto` makes and the exact
    /// reverse of the COPYFILE_UNPACK the extraction path already runs, so the
    /// bytes are macOS's own rather than our idea of the format. Deliberately
    /// without COPYFILE_DATA: the contents travel as the entry itself, and a
    /// sidecar that repeated them would double the size of the archive.
    ///
    /// It packs a stand-in rather than the file itself, because `copyfile` offers
    /// no way to leave an attribute out and some of them must not travel. The
    /// stand-in is given exactly the attributes worth keeping and then packed, so
    /// what lands in the archive is the same format either way.
    private static func packMetadata(of source: URL, into scratch: URL) throws -> URL {
        let donor = scratch.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.createFile(atPath: donor.path, contents: nil) else {
            throw metadataError("create", donor)
        }

        for name in try attributeNames(of: source) where !systemOwnedAttributes.contains(name) {
            let size = getxattr(source.path, name, nil, 0, 0, XATTR_NOFOLLOW)
            guard size >= 0 else { throw metadataError("getxattr \(name)", source) }

            var value = [UInt8](repeating: 0, count: max(size, 1))
            guard getxattr(source.path, name, &value, size, 0, XATTR_NOFOLLOW) == size else {
                throw metadataError("getxattr \(name)", source)
            }
            guard setxattr(donor.path, name, value, size, 0, XATTR_NOFOLLOW) == 0 else {
                throw metadataError("setxattr \(name)", donor)
            }
        }

        let destination = scratch.appendingPathComponent(UUID().uuidString)
        let flags = copyfile_flags_t(COPYFILE_PACK | COPYFILE_XATTR)
        guard copyfile(donor.path, destination.path, nil, flags) == 0 else {
            throw metadataError("copyfile", source)
        }
        return destination
    }

    /// What an AppleDouble looks like when there was nothing to put in it.
    ///
    /// A packed sidecar is never empty: `copyfile` writes a header and a zeroed
    /// FinderInfo whether or not the file had anything to say. Storing one per
    /// entry would roughly double the entry count of every archive for no gain,
    /// so a sidecar matching this sample is dropped instead.
    ///
    /// Sampled rather than hard-coded as a byte count, so that a change in what
    /// `copyfile` emits shows up as sidecars that are kept, rather than as real
    /// metadata quietly thrown away.
    private struct EmptyMetadata {
        private let sample: Data

        /// Throws rather than falling back to "nothing matches": a missing sample
        /// would quietly give every entry in the archive a sidecar carrying
        /// nothing, which is the failure this comparison exists to prevent.
        init(scratch: URL) throws {
            let file = scratch.appendingPathComponent("empty-metadata-sample")
            try Data().write(to: file)
            sample = try Data(contentsOf: packMetadata(of: file, into: scratch))
        }

        func describesNothing(_ sidecar: Data) -> Bool { sidecar == sample }
    }

    /// The sidecar entries to store alongside `items`.
    ///
    /// Both files and directories get one. A directory is not an afterthought
    /// here: a folder's custom icon is a picture in a hidden `Icon\r` file *plus*
    /// a flag on the folder itself, and restoring only the file leaves the folder
    /// looking generic. `ditto` writes no sidecar for a directory, which is why a
    /// round trip through Finder's "Compress" loses a custom folder icon.
    ///
    /// Symlinks are skipped: a link has no metadata worth carrying, and the
    /// extraction side refuses to unpack onto one anyway, since `copyfile` would
    /// follow it and write to whatever it points at.
    private static func metadataSidecars(for items: [ResolvedItem], scratch: URL) throws -> [ResolvedItem] {
        let empty = try EmptyMetadata(scratch: scratch)
        var sidecars: [ResolvedItem] = []

        for item in items {
            let archivePath: String
            let source: URL
            let date: Date?

            switch item {
            case .addFile(let path, let url, let modificationDate, _):
                (archivePath, source, date) = (path, url, modificationDate)
            case .addDirectory(let path, let url?, let modificationDate, _):
                (archivePath, source, date) = (path, url, modificationDate)
            default:
                continue
            }

            let values = try source.resourceValues(
                forKeys: [.isSymbolicLinkKey, .contentModificationDateKey])
            if values.isSymbolicLink == true { continue }

            // The only reason to leave a sidecar out: it was packed, and what came
            // back says nothing. A failure above is a failure, not an absence.
            let packed = try packMetadata(of: source, into: scratch)
            let bytes = try Data(contentsOf: packed)
            if empty.describesNothing(bytes) { continue }

            sidecars.append(.addFile(
                archivePath: sidecarPath(for: archivePath),
                diskPath: packed,
                // The sidecar carries the date of what it describes, as ditto's
                // do — its own would be the moment the archive happened to be
                // written, which says nothing about the file.
                modificationDate: date ?? values.contentModificationDate,
                posixPermissions: nil))
        }

        return sidecars
    }

    // MARK: - Bridge Call

    /// Box that carries the write-progress closure through the C callback.
    private final class WriteProgressBox {
        let handler: WriteProgressHandler
        init(_ handler: @escaping WriteProgressHandler) { self.handler = handler }
    }

    private static let writeProgressThunk: sz_progress_callback = { completed, total, context in
        guard let context else { return true }
        let box = Unmanaged<WriteProgressBox>.fromOpaque(context).takeUnretainedValue()
        return box.handler(completed, total)
    }

    private static func performUpdate(
        source: URL?,
        destination: URL,
        resolvedItems: [ResolvedItem],
        options: SevenZipCompressionOptions,
        progress: WriteProgressHandler? = nil
    ) throws {
        var cItems: [SZUpdateItem] = []
        cItems.reserveCapacity(resolvedItems.count)
        var dataRefs: [Data] = []

        for item in resolvedItems {
            var ci = SZUpdateItem()
            switch item {
            case .keep(let idx):
                ci.op = SZ_UPDATE_KEEP
                ci.source_index = idx
            case .move(let idx, _):
                ci.op = SZ_UPDATE_MOVE
                ci.source_index = idx
            case .addFile:
                ci.op = SZ_UPDATE_ADD_FILE
                ci.is_directory = false
            case .addData(_, let data, _, _):
                ci.op = SZ_UPDATE_ADD_DATA
                ci.is_directory = false
                ci.data_size = UInt64(data.count)
                dataRefs.append(data)
            case .addDirectory:
                ci.op = SZ_UPDATE_ADD_DIR
                ci.is_directory = true
            }
            cItems.append(ci)
        }

        let archivePaths = resolvedItems.map { item -> String? in
            switch item {
            case .move(_, let p): return p
            case .addFile(let p, _, _, _): return p
            case .addData(let p, _, _, _): return p
            case .addDirectory(let p, _, _, _): return p
            default: return nil
            }
        }

        let diskPaths = resolvedItems.map { item -> String? in
            if case .addFile(_, let url, _, _) = item {
                return url.path
            }
            return nil
        }

        let progressBox = progress.map(WriteProgressBox.init)

        try withExtendedLifetime(dataRefs) {
        try withExtendedLifetime(progressBox) {
            for i in 0..<cItems.count {
                cItems[i].mtime = -1
                switch resolvedItems[i] {
                case .keep, .move:
                    break
                case .addFile(_, _, let d, let p):
                    if let d { cItems[i].mtime = Int64(d.timeIntervalSince1970) }
                    if let p { cItems[i].posix_permissions = UInt32(p) }
                case .addData(_, _, let d, let p):
                    if let d { cItems[i].mtime = Int64(d.timeIntervalSince1970) }
                    // no permissions given: default to a regular 644 file —
                    // leaving them unset stores mode 000, which extracts as unreadable
                    cItems[i].posix_permissions = p.map(UInt32.init) ?? 0o100644
                case .addDirectory(_, _, let d, let p):
                    if let d { cItems[i].mtime = Int64(d.timeIntervalSince1970) }
                    cItems[i].posix_permissions = p.map(UInt32.init) ?? 0o40755
                }
            }

            try withArrayOfCStrings(archivePaths) { archivePathPtrs in
                try withArrayOfCStrings(diskPaths) { diskPathPtrs in
                    for i in 0..<cItems.count {
                        cItems[i].archive_path = archivePathPtrs[i]
                        cItems[i].disk_path = diskPathPtrs[i]
                    }

                    var dataIdx = 0
                    for i in 0..<cItems.count {
                        if case .addData = resolvedItems[i] {
                            cItems[i].data = (dataRefs[dataIdx] as NSData).bytes
                            dataIdx += 1
                        }
                    }

                    var cOptions = SZCompressionOptions()
                    let formatStr = options.format.rawValue
                    let methodStr = options.method?.rawValue

                    try formatStr.withCString { fmtPtr in
                        cOptions.format = fmtPtr
                        cOptions.level = options.level
                        cOptions.method = nil
                        cOptions.solid_mode = options.solidMode.map {
                            Int8($0 ? 1 : 0)
                        } ?? -1

                        let callBridge = { (methodPtr: UnsafePointer<CChar>?) throws in
                            cOptions.method = methodPtr
                            var errorPtr: UnsafeMutablePointer<CChar>?
                            let result = sz_update_archive(
                                source?.path,
                                destination.path,
                                &cItems,
                                UInt32(cItems.count),
                                &cOptions,
                                progressBox != nil ? Self.writeProgressThunk : nil,
                                progressBox.map { Unmanaged.passUnretained($0).toOpaque() },
                                &errorPtr
                            )
                            if result == 2 {
                                throw SevenZipError.cancelled
                            }
                            if result != 0 {
                                let msg = errorPtr.map { ptr -> String in
                                    let str = String(cString: ptr)
                                    free(ptr)
                                    return str
                                } ?? "Unknown error"
                                throw SevenZipError.writeFailed(msg)
                            }
                        }

                        if let m = methodStr {
                            try m.withCString { mPtr in
                                try callBridge(mPtr)
                            }
                        } else {
                            try callBridge(nil)
                        }
                    }
                }
            }
        }
        }
    }
}

// MARK: - C String Array Helper

/// Calls the closure with an array of optional C string pointers.
/// Uses strdup/free to guarantee pointer stability.
private func withArrayOfCStrings<R>(
    _ strings: [String?],
    _ body: ([UnsafePointer<CChar>?]) throws -> R
) rethrows -> R {
    let duped: [UnsafeMutablePointer<CChar>?] = strings.map { str in
        guard let s = str else { return nil }
        return strdup(s)
    }
    defer {
        for ptr in duped { free(ptr) }
    }
    let constPtrs: [UnsafePointer<CChar>?] = duped.map { ptr in
        ptr.map { UnsafePointer($0) }
    }
    return try body(constPtrs)
}
