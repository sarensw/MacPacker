//
//  ExtractionDemo.swift
//  MacPacker
//
//  Created by Claude on 13.07.26.
//

#if DEBUG
import Core
import Foundation

/// DEBUG-only preview of the extraction progress window with mock data. It lets
/// that window be shown — and screenshotted — in a known state without running
/// a real extraction. This is a test/preview aid, not a shipping feature; a real
/// build never fabricates progress.
///
///   -ExtractDemo 1   show the extraction window sitting at 1/3 of a large file
@MainActor
enum ExtractionDemo {
    /// Resolved through `LaunchParameters` so it honors both a real `-ExtractDemo`
    /// argument and one set by SandboxPilot.
    static var isRequested: Bool { LaunchParameters.isExtractDemo }

    /// One running job sitting at 1/3 of a large file, with enough throughput
    /// samples that the details chart draws a visible rising curve. The job is
    /// never finished, so the window stays open.
    static func applyIfRequested() {
        guard isRequested else { return }

        let center = ExtractionProgressCenter.shared
        let total: Int64 = 3_000_000_000            // ~3 GB — a "large file"
        let target: Int64 = total / 3               // 1/3 progress
        let id = center.begin(
            archiveName: "PresentationAssets.dmg",
            destination: URL(fileURLWithPath: "/Users/Shared"),
            itemCount: 1,
            totalBytes: total
        )

        // Feed the reports over REAL time (not a synchronous burst): the chart's
        // y-scale is driven by the running average = completedBytes / elapsed,
        // and a burst makes elapsed ~0 → an astronomical average that flattens
        // the speed line to the floor. Spacing the reports keeps the sample
        // speeds and the average on the same clock.
        //
        // `shape` is the relative instantaneous throughput per report: a quick
        // ramp, a wobbly plateau, and a sustained mid dip with recovery — what a
        // real disk extraction looks like, not a smooth monotonic climb. Deltas
        // are proportional to it (constant time step), and the positions are
        // normalized so the run lands exactly on 1/3.
        Task { @MainActor in
            let shape: [Double] = [
                0.18, 0.5, 0.85, 1.1, 1.15, 1.05, 0.95, 0.7, 0.55, 0.5,
                0.68, 0.92, 1.12, 1.2, 1.08, 0.95, 1.06, 1.0,
            ]
            let totalWeight = shape.reduce(0, +)
            var acc = 0.0
            for weight in shape {
                acc += weight
                let completed = Int64((Double(target) * acc / totalWeight).rounded())
                center.reportEngineProgress(id, completed: completed, total: total)
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }
}
#endif
