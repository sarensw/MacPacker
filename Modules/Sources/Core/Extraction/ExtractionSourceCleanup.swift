import Foundation
import CryptoKit

/// Captures the source set before extraction, then refuses cleanup if any part
/// changed. Only a caller that successfully extracted the whole archive may use it.
struct ExtractionSourceCleanup {
    let sources: [URL]
    private let stamps: [SourceIdentity]

    init(source: URL, catalog: ArchiveTypeCatalog) throws {
        let directory = source.deletingLastPathComponent()
        let siblings = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let detector = ArchiveTypeDetector(catalog: catalog)
        var candidates = [source]
        if let split = detector.detect(for: source)?.split {
            let first = SplitVolumeResolver.firstVolume(for: source, split: split)
            candidates = siblings.filter {
                guard let other = detector.detect(for: $0)?.split, other.format == split.format else { return $0.standardizedFileURL.path == first.standardizedFileURL.path }
                return SplitVolumeResolver.firstVolume(for: $0, split: other).standardizedFileURL.path == first.standardizedFileURL.path
            }
        } else if source.pathExtension.lowercased() == "rar" {
            // The first legacy RAR volume has no multipart suffix itself.
            candidates += siblings.filter {
                guard let split = detector.detect(for: $0)?.split, split.scheme == "rar-legacy" else { return false }
                return SplitVolumeResolver.firstVolume(for: $0, split: split).standardizedFileURL.path == source.standardizedFileURL.path
            }
        }
        sources = Array(Set(candidates)).sorted { $0.path < $1.path }
        stamps = try sources.map(SourceIdentity.init)

    }

    /// Validates all sources before removal and restores prior moves if one fails.
    func perform(trash: (URL) throws -> URL = { url in
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        guard let result else { throw ArchiveError.extractionFailed("Trash did not report the recovery location.") }
        return result as URL
    }) throws {
        guard !sources.isEmpty, try sources.map(SourceIdentity.init) == stamps else {
            throw ArchiveError.extractionFailed("Extraction finished, but the source changed. The archive was kept.")
        }
        var moved: [(original: URL, trashed: URL)] = []
        do {
            for (source, stamp) in zip(sources, stamps) {
                guard try SourceIdentity(source) == stamp else {
                    throw ArchiveError.extractionFailed("The source archive changed during cleanup.")
                }
                moved.append((source, try trash(source)))
            }
        } catch {
            var recovery: [String] = []
            for item in moved.reversed() {
                do { try FileManager.default.moveItem(at: item.trashed, to: item.original) }
                catch { recovery.append(item.trashed.path) }
            }
            if !recovery.isEmpty {
                throw ArchiveError.extractionFailed("Source cleanup was incomplete. Recover remaining files from: " + recovery.joined(separator: ", "))
            }
            throw error
        }
    }
}

/// File identity plus streaming content verification, including unchanged-size edits.
private struct SourceIdentity: Equatable {
    let device: UInt64
    let inode: UInt64
    let digest: Data

    init(_ url: URL) throws {
        let fm = FileManager.default
        let before = try fm.attributesOfItem(atPath: url.path)
        guard before[.type] as? FileAttributeType == .typeRegular,
              let device = before[.systemNumber] as? NSNumber,
              let inode = before[.systemFileNumber] as? NSNumber else {
            throw ArchiveError.extractionFailed("Cannot verify the source archive identity.")
        }
        self.device = device.uint64Value
        self.inode = inode.uint64Value
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
        digest = Data(hash.finalize())
        let after = try fm.attributesOfItem(atPath: url.path)
        for key: FileAttributeKey in [.systemNumber, .systemFileNumber, .size, .modificationDate] {
            guard (before[key] as? NSObject) == (after[key] as? NSObject) else {
                throw ArchiveError.extractionFailed("The source archive changed while verifying it.")
            }
        }
    }
}
