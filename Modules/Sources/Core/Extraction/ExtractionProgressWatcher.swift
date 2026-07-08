//
//  ExtractionProgressWatcher.swift
//  Modules
//
//  Created by Claude on 09.07.26.
//

import Foundation

/// Measures extraction progress by watching the byte growth of the
/// directories an extraction writes into.
///
/// None of the engines (7zip bridge, XADMaster, SWCompression) reports
/// byte-level progress callbacks, and the vendored libraries must stay
/// pristine. Sampling the output directories is engine-agnostic and accurate
/// enough for a progress bar.
/// ponytail: polling at ~2.5 Hz; upgrade path is real progress callbacks in
/// our Swift7zip bridge if sampling ever proves too coarse.
public actor ExtractionProgressWatcher {
    private var watched: [URL] = []
    private var baselines: [URL: Int64] = [:]

    public init() {}

    /// Starts watching a directory. Bytes already present count as baseline
    /// and are subtracted from every sample, so watching a non-empty
    /// destination (full-archive extraction) reports only the new bytes.
    public func watch(_ url: URL) {
        guard baselines[url] == nil else { return }
        watched.append(url)
        baselines[url] = Self.bytes(at: url)
    }

    /// Total bytes written into all watched directories since `watch`.
    public func sampleCompletedBytes() -> Int64 {
        watched.reduce(Int64(0)) { sum, url in
            sum + max(0, Self.bytes(at: url) - (baselines[url] ?? 0))
        }
    }

    /// Polls in the background and pushes samples into the center until the
    /// returned task is cancelled.
    public nonisolated func startReporting(
        to center: ExtractionProgressCenter,
        jobId: UUID,
        every interval: Duration = .milliseconds(400)
    ) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                let bytes = await self.sampleCompletedBytes()
                await center.report(jobId, completedBytes: bytes)
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Recursive logical file size of a directory tree.
    private static func bytes(at url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  let size = values.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }
}
