//
//  ExtractionProgressCenter.swift
//  Modules
//
//  Created by Claude on 09.07.26.
//

import Foundation
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "extraction")

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
    /// Expected total uncompressed bytes. `nil` means unknown — show an
    /// indeterminate progress bar.
    public let totalBytes: Int64?
    public internal(set) var completedBytes: Int64 = 0
    public let startedAt: Date
    public internal(set) var finishedAt: Date?
    public internal(set) var state: State = .running

    public var isFinished: Bool { state != .running }

    /// 0...1 while the total is known, nil for indeterminate progress.
    public var fractionCompleted: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(1.0, Double(completedBytes) / Double(totalBytes))
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

    public func report(_ id: UUID, completedBytes: Int64) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), !jobs[index].isFinished else { return }
        jobs[index].completedBytes = max(0, completedBytes)
    }

    /// Moves a job into a terminal state. Later calls for the same job are ignored.
    public func finish(_ id: UUID, _ state: ExtractionJob.State) {
        guard state != .running else { return }
        guard let index = jobs.firstIndex(where: { $0.id == id }), !jobs[index].isFinished else { return }
        jobs[index].state = state
        jobs[index].finishedAt = Date()
        if state == .done, let total = jobs[index].totalBytes {
            jobs[index].completedBytes = total
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
