import Foundation

/// Captures the source set before extraction, then refuses cleanup if any part
/// changed. Only a caller that successfully extracted the whole archive may use it.
struct ExtractionSourceCleanup {
    let sources: [URL]
    private let stamps: [FileStamp]

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
        stamps = try sources.map { url in
            guard let stamp = FileStamp(url) else { throw ArchiveError.extractionFailed("Cannot verify the source archive before extraction.") }
            return stamp
        }
    }

    func perform(trash: (URL) throws -> Void = { url in
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }) throws {
        guard !sources.isEmpty, sources.map({ FileStamp($0) }) == stamps.map({ Optional($0) }) else {
            throw ArchiveError.extractionFailed("Extraction finished, but the source changed. The archive was kept.")
        }
        for source in sources { try trash(source) }
    }
}
