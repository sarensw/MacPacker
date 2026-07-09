//
//  ExtractionProgressWatcher.swift
//  Modules
//
//  Created by Claude on 09.07.26.
//

import Foundation
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "extraction")

/// Measures extraction progress by watching the bytes an extraction writes
/// into its output directories.
///
/// None of the engines (7zip bridge, XADMaster, SWCompression) reports
/// byte-level progress callbacks, and the vendored libraries must stay
/// pristine. Sampling the output directories is engine-agnostic and accurate
/// enough for a progress bar.
///
/// A file counts when it was *touched since the job started* (ctime): stale
/// output of an earlier run at the same destination — including leftovers of
/// a crashed run — is ignored, and files it overwrites in place count at
/// their full current size. A size-delta baseline can't do that: overwrites
/// keep the delta at or below zero and pin the bar. mtime is unusable
/// because the engines restore the archive's original timestamps; ctime
/// cannot be set backwards.
/// ponytail: polling at ~2.5 Hz; upgrade path is real progress callbacks in
/// our Swift7zip bridge if sampling ever proves too coarse.
public actor ExtractionProgressWatcher {
    private let startedAt: Date
    private var watched: [URL] = []

    public init(startedAt: Date = Date()) {
        self.startedAt = startedAt
    }

    /// Starts watching a directory.
    public func watch(_ url: URL) {
        guard !watched.contains(url) else { return }
        watched.append(url)
    }

    /// Total bytes of files touched since the job started, across all
    /// watched directories.
    public func sampleCompletedBytes() -> Int64 {
        watched.reduce(Int64(0)) { sum, url in
            sum + Self.bytesTouched(at: url, since: startedAt)
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
            var iteration = 0
            while !Task.isCancelled {
                let bytes = await self.sampleCompletedBytes()
                await center.report(jobId, completedBytes: bytes)
                iteration += 1
                if iteration % 25 == 0 {
                    log.debug("Progress sample", context: [
                        "job": jobId.uuidString,
                        "iteration": "\(iteration)",
                        "bytes": "\(bytes)"
                    ])
                }
                try? await Task.sleep(for: interval)
            }
            log.debug("Progress polling ended", context: [
                "job": jobId.uuidString,
                "iterations": "\(iteration)"
            ])
        }
    }

    /// Recursive sum of the sizes of regular files whose ctime is at or
    /// after `threshold`.
    ///
    /// Attributes are read per file via `lstat`: it reports the live vnode
    /// size of files that are currently being written. The enumerator's
    /// prefetched URL resource values (getattrlistbulk) serve catalog-cached
    /// sizes that lag far behind an active writer — that made the progress
    /// UI freeze on large single-file extractions.
    private static func bytesTouched(at url: URL, since threshold: Date) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [],
            options: []
        ) else { return 0 }

        let thresholdSeconds = threshold.timeIntervalSince1970
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            var status = stat()
            guard lstat(fileURL.path, &status) == 0,
                  (status.st_mode & S_IFMT) == S_IFREG else { continue }

            let changedAt = TimeInterval(status.st_ctimespec.tv_sec)
                + TimeInterval(status.st_ctimespec.tv_nsec) / 1_000_000_000
            guard changedAt >= thresholdSeconds else { continue }

            total += Int64(status.st_size)
        }
        return total
    }
}
