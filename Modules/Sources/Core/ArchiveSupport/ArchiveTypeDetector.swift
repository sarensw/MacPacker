//
//  ArchiveTypeIdentifier.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 01.11.25.
//

import Foundation
import UniformTypeIdentifiers
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "archive")

public enum DetectionSource: String {
    case fileExtension
    case systemUTI
    case magic
    case combined
}

public struct DetectionResult: CustomStringConvertible {
    public let type: ArchiveTypeDto
    public let composition: CompositionTypeDto?
    /// Non-nil when the file is a *volume part* of a split / multi-volume archive
    /// of `type` — carries the scheme and the first-volume rule.
    public let split: SplitTypeDto?
    public let source: DetectionSource

    public init(
        type: ArchiveTypeDto,
        composition: CompositionTypeDto? = nil,
        split: SplitTypeDto? = nil,
        source: DetectionSource
    ) {
        self.type = type
        self.composition = composition
        self.split = split
        self.source = source
    }

    public var description: String {
        if let composition { return "\(type) (\(composition))" }
        if let split { return "\(type) [split: \(split.scheme)]" }
        return "\(type)"
    }
}

final public class ArchiveTypeDetector: Sendable {
    private let catalog: ArchiveTypeCatalog

    public init(catalog: ArchiveTypeCatalog) {
        self.catalog = catalog
    }

    public func getNameWithoutExtension(for url: URL) -> String {
        var name = url.lastPathComponent
        // `detectByExtension` matches case-insensitively, so a `MyArchive.ZIP`
        // is recognized as a zip — the suffix test here must be case-insensitive
        // too, or the extension is never stripped. Compare against a lowercased
        // view of the name, but remove from the original so the base name keeps
        // its casing (MyArchive.ZIP → "MyArchive").
        let lowercasedName = name.lowercased()
        if let byExt = detectByExtension(for: url, considerComposition: true) {
            if let composition = byExt.composition {
                for compExt in composition.extensions {
                    if lowercasedName.hasSuffix(".\(compExt)") {
                        name.removeLast(compExt.count + 1)
                        break
                    }
                }
            } else if let split = byExt.split {
                // A split/multi-volume part (.z03, .zip.005) is detected by its
                // own $-anchored regex; strip that suffix so the folder is named
                // after the archive base (MyArchive.z03 → "MyArchive"). Detection
                // is case-insensitive, so the strip must be too — but we replace
                // in the original `name` to keep the base name's casing.
                name = name.replacingOccurrences(
                    of: split.pattern,
                    with: "",
                    options: [.regularExpression, .caseInsensitive]
                )
            } else {
                for ext in byExt.type.extensions {
                    if lowercasedName.hasSuffix(".\(ext)") {
                        name.removeLast(ext.count + 1)
                        break
                    }
                }
            }
        }
        return name
    }

    /// Classify `url` into `(format [, composition] [, split])`:
    ///   Phase 1 — by extension: compound → split part → plain format.
    ///   Phase 2 — by magic bytes, only when the extension told us nothing.
    ///   Phase 3 — for a plain format, a content probe for the one ambiguous case
    ///             (a bare `.zip` that is really a spanned terminal volume).
    public func detect(for url: URL, considerComposition: Bool = true) -> DetectionResult? {
        if let byExt = detectByExtension(for: url, considerComposition: considerComposition) {
            // A split part matched by its extension already carries its scheme; a
            // plain format still needs the content probe.
            return byExt.split != nil ? byExt : attachSplitMarker(byExt, url: url)
        }

        if let byMagic = detectByMagicNumber(for: url) {
            return attachSplitMarker(byMagic, url: url)
        }

        return nil
    }

    func detectBy(ext: String, considerComposition: Bool = true) -> DetectionResult? {
        let dummyUrl = URL(fileURLWithPath: "fakePath.\(ext)")
        return detectByExtension(for: dummyUrl, considerComposition: considerComposition)
    }

    /// Phase 1 — identify by extension: compound (`tar.gz`) → split part (`.z01`,
    /// `.zip.001`) → plain format. Compounds and splits both point back to a base
    /// format; a split match also carries the scheme + first-volume rule.
    func detectByExtension(for url: URL, considerComposition: Bool) -> DetectionResult? {
        let name = url.lastPathComponent.lowercased()

        // 1. compound (e.g. tar.gz)
        if considerComposition {
            for composition in catalog.allCompositions() {
                for ext in composition.extensions where name.hasSuffix(".\(ext.lowercased())") {
                    if let baseType = catalog.getType(for: composition.components.first!) {
                        return DetectionResult(type: baseType, composition: composition, source: .fileExtension)
                    } else {
                        log.error("Composition found, but could not retrieve the base type for \(ext)")
                    }
                }
            }
        }

        // 2. split volume part by extension (e.g. .z01, .zip.001) → points back to its format
        for split in catalog.allSplits()
        where name.range(of: split.pattern, options: [.regularExpression, .caseInsensitive]) != nil {
            if let baseType = catalog.getType(for: split.format) {
                return DetectionResult(type: baseType, split: split, source: .fileExtension)
            } else {
                log.error("Split type \(split.id) references unknown format \(split.format)")
            }
        }

        // 3. plain format by extension
        let lc = url.pathExtension.lowercased()
        if let type = catalog.getType(where: { $0.extensions.contains(lc) }) {
            return DetectionResult(type: type, source: .fileExtension)
        }

        return nil
    }

    // MARK: - Phase 3: content split probe (the ambiguous bare `.zip`)

    /// For a plain-format match with no split yet, test that format's split types'
    /// content `marker`s — e.g. the zip EOCD disk field — so a bare `.zip` that is
    /// really a spanned terminal volume is recognized.
    private func attachSplitMarker(_ result: DetectionResult, url: URL) -> DetectionResult {
        guard result.split == nil else { return result }
        let splits = catalog.allSplits().filter { $0.format == result.type.id && $0.marker != nil }
        guard !splits.isEmpty, let tail = readTail(of: url) else { return result }

        for split in splits where matchesMarker(split.marker!, in: tail) {
            return DetectionResult(
                type: result.type,
                composition: result.composition,
                split: split,
                source: result.source
            )
        }
        return result
    }

    /// Find the last occurrence of `marker.bytes` in the tail, then test the field
    /// at `field.offset`/`field.length` from it (e.g. EOCD disk number ≠ 0).
    private func matchesMarker(_ marker: SplitMarkerDto, in bytes: [UInt8]) -> Bool {
        let sig = marker.bytes
        guard !sig.isEmpty, bytes.count >= sig.count else { return false }

        var sigStart: Int? = nil
        var i = bytes.count - sig.count
        while i >= 0 {
            if Array(bytes[i..<i + sig.count]) == sig { sigStart = i; break }
            i -= 1
        }
        guard let s = sigStart else { return false }

        let fStart = s + marker.field.offset, fEnd = fStart + marker.field.length
        guard fStart >= 0, fEnd <= bytes.count else { return false }
        switch marker.field.match {
        case "nonzero": return bytes[fStart..<fEnd].contains { $0 != 0 }
        default: return false
        }
    }

    // MARK: - Phase 2: magic-number format identity

    func getFileSize(for url: URL) -> UInt64? {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
            return UInt64(resourceValues.fileSize ?? 0)
        } catch {
            log.error("Error getting file size: \(error.localizedDescription)")
            return nil
        }
    }

    func detectByMagicNumber(for url: URL) -> DetectionResult? {
        // Reached with nothing but a stored bookmark when the file is opened from
        // the recents list or by `-ArchivePath`: no scope, no read, and the archive
        // then looks like an unsupported file.
        Sandbox.accessSync(url: url) { detectByMagicNumberInScope(for: url) }
    }

    private func detectByMagicNumberInScope(for url: URL) -> DetectionResult? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { handle.closeFile() }

        // read the first 65.536 bytes (iso files are detected at 0x8000..0x9000)
        guard let headerData = try? handle.read(upToCount: 65536), !headerData.isEmpty else { return nil }
        let headerBytes = [UInt8](headerData)

        // read the last 512 bytes (big enough for e.g. a dmg's koly trailer)
        guard let fileSize = getFileSize(for: url) else { return nil }
        let trailerSize = min(fileSize, 512)
        do { try handle.seek(toOffset: fileSize - trailerSize) } catch { return nil }
        guard let trailerData = try? handle.read(upToCount: Int(trailerSize)), !trailerData.isEmpty else { return nil }
        let trailerBytes = [UInt8](trailerData)

        for type in catalog.getAllTypes() {
            for group in type.rules where matches(group, header: headerBytes, trailer: trailerBytes) {
                return DetectionResult(type: type, source: .magic)
            }
        }
        return nil
    }

    private func matches(_ group: RuleGroupDto, header: [UInt8], trailer: [UInt8]) -> Bool {
        switch group.policy {
        case .any: return group.tests.contains { matches($0, header: header, trailer: trailer) }
        case .all: return group.tests.allSatisfy { matches($0, header: header, trailer: trailer) }
        }
    }

    private func matches(_ test: RuleTestDto, header: [UInt8], trailer: [UInt8]) -> Bool {
        switch test.type {
        case "end_signature":
            let start = trailer.count - test.offset, end = start + test.bytes.count
            guard start >= 0, end <= trailer.count else { return false }
            return Array(trailer[start..<end]) == test.bytes
        default: // "signature" — bytes at a fixed offset from the start
            let start = test.offset, end = start + test.bytes.count
            guard start >= 0, end <= header.count else { return false }
            return Array(header[start..<end]) == test.bytes
        }
    }

    /// Reads up to `maxBytes` from the end of the file, for a split `marker`
    /// (the zip EOCD can sit anywhere in the last 64 KiB + comment).
    /// Same bookmark caveat as `detectByMagicNumber` — a tail read that silently
    /// fails costs the split marker, so a spanned set would load as a lone volume.
    private func readTail(of url: URL, maxBytes: Int = 65557) -> [UInt8]? {
        Sandbox.accessSync(url: url) { readTailInScope(of: url, maxBytes: maxBytes) }
    }

    private func readTailInScope(of url: URL, maxBytes: Int) -> [UInt8]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { handle.closeFile() }
        guard let size = getFileSize(for: url), size > 0 else { return nil }
        let n = min(UInt64(maxBytes), size)
        do { try handle.seek(toOffset: size - n) } catch { return nil }
        guard let data = try? handle.read(upToCount: Int(n)), !data.isEmpty else { return nil }
        return [UInt8](data)
    }
}
