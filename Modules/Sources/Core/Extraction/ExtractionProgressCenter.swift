//
//  ExtractionProgressCenter.swift
//  Modules
//
//  Created by Claude on 09.07.26.
//

import Foundation
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "extraction")

/// One point of the throughput history shown in the details chart.
public struct ExtractionSpeedSample: Equatable, Sendable {
    /// Seconds since the job started.
    public let elapsed: TimeInterval
    /// Progress at sampling time — lets the chart plot speed over transfer
    /// position, so the area builds up left to right like the Windows
    /// copy dialog.
    public let completedBytes: Int64
    public let bytesPerSecond: Double
}

/// One user-visible extraction run (e.g. "extract selected items to folder X").
public struct ExtractionJob: Identifiable, Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case running
        case done
        case failed(String)
        case cancelled
    }

    public let id: UUID
    public let archiveName: String
    public let destination: URL?
    public let itemCount: Int
    /// Expected total uncompressed bytes from the archive listing. `nil`
    /// means unknown — show an indeterminate progress bar.
    public let totalBytes: Int64?
    /// Total reported by the engine itself, in the engine's own byte unit.
    /// When present it supersedes `totalBytes` (same unit as the engine's
    /// completed counter, so fractions stay consistent).
    public internal(set) var engineTotalBytes: Int64?
    /// True once the engine reported progress directly — directory sampling
    /// is ignored from then on so the two sources can't fight.
    var hasEngineProgress: Bool = false
    public internal(set) var completedBytes: Int64 = 0
    public let startedAt: Date
    public internal(set) var finishedAt: Date?
    public internal(set) var state: State = .running

    /// Speed points for the details graph: the transfer is divided into
    /// `maxSpeedSamples` uniform slots, and crossing a slot boundary records
    /// the instantaneous speed at that moment. Points are append-only — raw
    /// values, nothing averaged, normalized, or rewritten, so drawn history
    /// is immutable by construction. Without a known total, one point per
    /// report up to the same cap.
    public internal(set) var speedSamples: [ExtractionSpeedSample] = []
    public static let maxSpeedSamples = 420
    /// Causal smoothing factor: each recorded point blends the newest raw
    /// speed with the running average, applied at record time only — drawn
    /// points never change afterwards. α = 2/(N+1) with N = 10, i.e. the
    /// average effectively covers the last ten reports.
    public static let speedSmoothing = 2.0 / 11.0
    var smoothedSpeed: Double = 0
    var lastReportAt: Date?
    var lastReportBytes: Int64 = 0

    public var isFinished: Bool { state != .running }

    /// The total used for fractions and display: the engine's own total
    /// when it reports progress, the listing total otherwise.
    public var effectiveTotalBytes: Int64? {
        engineTotalBytes ?? totalBytes
    }

    /// 0...1 while the total is known, nil for indeterminate progress.
    public var fractionCompleted: Double? {
        guard let total = effectiveTotalBytes, total > 0 else { return nil }
        return min(1.0, Double(completedBytes) / Double(total))
    }

    /// Most recent throughput sample.
    public var currentBytesPerSecond: Double {
        speedSamples.last?.bytesPerSecond ?? 0
    }

    /// Bytes per second averaged over the whole run so far.
    public var averageBytesPerSecond: Double {
        let elapsed = (finishedAt ?? Date()).timeIntervalSince(startedAt)
        guard elapsed > 0 else { return 0 }
        return Double(completedBytes) / elapsed
    }

    /// Rough time-to-finish estimate from the current speed (falls back to
    /// the average). nil when the total or the speed is unknown.
    public var estimatedSecondsRemaining: TimeInterval? {
        guard state == .running, let total = effectiveTotalBytes, total > 0 else { return nil }
        let speed = currentBytesPerSecond > 0 ? currentBytesPerSecond : averageBytesPerSecond
        guard speed > 0 else { return nil }
        return max(0, Double(total - completedBytes)) / speed
    }

    mutating func recordSpeed(completedBytes bytes: Int64, at date: Date) {
        let previousAt = lastReportAt ?? startedAt
        let dt = date.timeIntervalSince(previousAt)
        guard dt > 0 else { return }

        let clamped = max(0, bytes)
        let raw = max(0, Double(clamped - lastReportBytes) / dt)
        // exponential moving average over the incoming raw speeds — smooths
        // the line a bit without ever rewriting already recorded points
        smoothedSpeed = smoothedSpeed == 0 ? raw : raw * Self.speedSmoothing + smoothedSpeed * (1 - Self.speedSmoothing)
        let speed = smoothedSpeed
        let elapsed = date.timeIntervalSince(startedAt)
        lastReportAt = date
        lastReportBytes = clamped

        guard let total = effectiveTotalBytes, total > 0 else {
            // ponytail: indeterminate totals are rare — one raw point per
            // report, hard-capped; the graph is secondary there anyway
            if speedSamples.count <= Self.maxSpeedSamples {
                speedSamples.append(ExtractionSpeedSample(
                    elapsed: elapsed, completedBytes: clamped, bytesPerSecond: speed
                ))
            }
            return
        }

        // anchor the graph at the origin with the first observed speed
        if speedSamples.isEmpty {
            speedSamples.append(ExtractionSpeedSample(elapsed: 0, completedBytes: 0, bytesPerSecond: speed))
        }

        // fill every slot whose boundary this report crossed with the
        // current raw speed
        while speedSamples.count - 1 < Self.maxSpeedSamples {
            let nextSlot = Int64(speedSamples.count)
            let boundary = total * nextSlot / Int64(Self.maxSpeedSamples)
            guard clamped >= boundary else { break }
            speedSamples.append(ExtractionSpeedSample(
                elapsed: elapsed, completedBytes: boundary, bytesPerSecond: speed
            ))
        }
    }
}

/// Global registry of running extractions. All archive windows (and the
/// window-less Finder-extension flows) report here so one progress window
/// can show everything that is being extracted right now.
@MainActor
public final class ExtractionProgressCenter: ObservableObject {
    public static let shared = ExtractionProgressCenter()

    @Published public private(set) var jobs: [ExtractionJob] = []

    private var cancelHandlers: [UUID: () -> Void] = [:]

    public init() {}

    public var hasActiveJobs: Bool {
        jobs.contains { !$0.isFinished }
    }

    /// Registers a new running job and returns its id.
    @discardableResult
    public func begin(
        archiveName: String,
        destination: URL?,
        itemCount: Int,
        totalBytes: Int64?
    ) -> UUID {
        let job = ExtractionJob(
            id: UUID(),
            archiveName: archiveName,
            destination: destination,
            itemCount: itemCount,
            totalBytes: totalBytes,
            startedAt: Date()
        )
        jobs.append(job)
        log.notice("Extraction job started", context: [
            "job": job.id.uuidString,
            "archive": archiveName,
            "destination": destination?.path ?? "(temp)",
            "items": "\(itemCount)",
            "totalBytes": totalBytes.map { "\($0)" } ?? "unknown"
        ])
        return job.id
    }

    /// Lets the owner of the extraction task hook up cancellation after the
    /// task handle exists. The UI triggers it through `requestCancel`.
    public func setOnCancel(_ id: UUID, _ handler: @escaping () -> Void) {
        guard let job = jobs.first(where: { $0.id == id }), !job.isFinished else { return }
        cancelHandlers[id] = handler
    }

    /// Called by the UI. Fires the cancel handler once; the job itself stays
    /// running until the extraction task acknowledges with `finish(_, .cancelled)`.
    public func requestCancel(_ id: UUID) {
        guard let handler = cancelHandlers.removeValue(forKey: id) else { return }
        log.notice("Extraction cancel requested", context: ["job": id.uuidString])
        handler()
    }

    /// Directory-sampled progress (fallback for engines without callbacks).
    /// Ignored once the engine reports progress directly.
    public func report(_ id: UUID, completedBytes: Int64, at date: Date = Date()) {
        guard let index = jobs.firstIndex(where: { $0.id == id }),
              !jobs[index].isFinished,
              !jobs[index].hasEngineProgress else { return }
        jobs[index].completedBytes = max(0, completedBytes)
        jobs[index].recordSpeed(completedBytes: max(0, completedBytes), at: date)
    }

    /// Byte progress reported by the extraction engine itself.
    /// `date` must be the time the engine emitted the values — reports may
    /// arrive on the main queue in bursts, and speed math needs the real
    /// emission spacing.
    public func reportEngineProgress(_ id: UUID, completed: Int64, total: Int64, at date: Date) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), !jobs[index].isFinished else { return }
        jobs[index].hasEngineProgress = true
        if total > 0 {
            jobs[index].engineTotalBytes = total
        }
        jobs[index].completedBytes = max(0, completed)
        jobs[index].recordSpeed(completedBytes: max(0, completed), at: date)
    }

    /// Moves a job into a terminal state. Later calls for the same job are ignored.
    public func finish(_ id: UUID, _ state: ExtractionJob.State) {
        guard state != .running else { return }
        guard let index = jobs.firstIndex(where: { $0.id == id }), !jobs[index].isFinished else { return }
        jobs[index].state = state
        jobs[index].finishedAt = Date()
        if state == .done, let total = jobs[index].effectiveTotalBytes {
            jobs[index].completedBytes = total
            // complete the graph to the right edge at the last known speed
            // (the final slots may not have seen a report before finishing)
            let lastSpeed = jobs[index].speedSamples.last?.bytesPerSecond ?? 0
            let elapsed = jobs[index].finishedAt?.timeIntervalSince(jobs[index].startedAt) ?? 0
            while jobs[index].speedSamples.count - 1 < ExtractionJob.maxSpeedSamples,
                  !jobs[index].speedSamples.isEmpty {
                let nextSlot = Int64(jobs[index].speedSamples.count)
                let boundary = total * nextSlot / Int64(ExtractionJob.maxSpeedSamples)
                jobs[index].speedSamples.append(ExtractionSpeedSample(
                    elapsed: elapsed, completedBytes: boundary, bytesPerSecond: lastSpeed
                ))
            }
        }
        cancelHandlers[id] = nil

        let duration = Date().timeIntervalSince(jobs[index].startedAt)
        switch state {
        case .done:
            log.notice("Extraction job done", context: [
                "job": id.uuidString,
                "archive": jobs[index].archiveName,
                "seconds": String(format: "%.2f", duration)
            ])
        case .failed(let message):
            log.error("Extraction job failed", context: [
                "job": id.uuidString,
                "archive": jobs[index].archiveName,
                "error": message
            ])
        case .cancelled:
            log.notice("Extraction job cancelled", context: [
                "job": id.uuidString,
                "archive": jobs[index].archiveName
            ])
        case .running:
            break
        }
    }

    /// Drops all finished jobs (the progress window calls this when it closes).
    public func clearFinished() {
        jobs.removeAll { $0.isFinished }
    }
}
