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
    public static func writeArchive(
        source: URL? = nil,
        destination: URL,
        items: [ArchiveUpdateItem],
        options: SevenZipCompressionOptions = .init()
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
        let resolved = try resolveDiff(source: source, items: items)

        try performUpdate(
            source: source,
            destination: actualDest,
            resolvedItems: resolved,
            options: options
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
        case addDirectory(archivePath: String,
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
            case .addDirectory(let p, let d, let perms):
                additions.append(.addDirectory(
                    archivePath: p, modificationDate: d,
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

    // MARK: - Bridge Call

    private static func performUpdate(
        source: URL?,
        destination: URL,
        resolvedItems: [ResolvedItem],
        options: SevenZipCompressionOptions
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
            case .addDirectory(let p, _, _): return p
            default: return nil
            }
        }

        let diskPaths = resolvedItems.map { item -> String? in
            if case .addFile(_, let url, _, _) = item {
                return url.path
            }
            return nil
        }

        try withExtendedLifetime(dataRefs) {
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
                    if let p { cItems[i].posix_permissions = UInt32(p) }
                case .addDirectory(_, let d, let p):
                    if let d { cItems[i].mtime = Int64(d.timeIntervalSince1970) }
                    if let p { cItems[i].posix_permissions = UInt32(p) }
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
                                &errorPtr
                            )
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
