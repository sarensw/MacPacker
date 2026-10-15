//
//  WindowExtractionProgressView.swift
//  MacPacker
//
//  An archive window's own extractions, at its foot above the status bar:
//  what the progress window shows for a job, without one more window on the
//  screen. Finder's actions have no window, and keep the progress window; so
//  does a window's extraction once the window has closed.
//

import Core
import SwiftUI

/// The rows of the window's own extractions, the progress window's row each;
/// nothing at all while there are none to show.
struct WindowExtractionProgressView: View {
    @ObservedObject var center: ExtractionProgressCenter
    /// The window's id, which its jobs carry (`ArchiveState.windowID`).
    let window: UUID
    @State private var expandedJobs: Set<UUID> = []
    /// The jobs that have lasted long enough to be shown.
    @State private var shown: Set<UUID> = []

    private var allJobs: [ExtractionJob] { center.jobs(shownIn: window) }

    /// As in the progress window, a job over within a moment is never shown —
    /// a small extraction does not make the table jump — unless it failed.
    private var jobs: [ExtractionJob] {
        allJobs.filter { shown.contains($0.id) || Self.hasFailed($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !jobs.isEmpty {
                Divider()
                    .frame(height: 1)
                    .background(.quinary)

                if jobs.count <= 3 {
                    rows
                } else {
                    // several at once: the table keeps most of the window
                    ScrollView {
                        rows
                    }
                    .frame(height: 220)
                }
            }
        }
        .background(jobs.isEmpty ? AnyShapeStyle(.clear) : AnyShapeStyle(.bar))
        .task(id: allJobs.map(\.id)) {
            // jobs that are gone are forgotten
            shown.formIntersection(allJobs.map(\.id))
            let pending = allJobs.filter { !shown.contains($0.id) }.map(\.id)
            guard !pending.isEmpty else { return }
            do {
                try await Task.sleep(for: .seconds(0.6))
            } catch {
                return
            }
            for id in pending {
                guard let job = allJobs.first(where: { $0.id == id }) else { continue }
                if !job.isFinished {
                    shown.insert(id)
                } else if !Self.hasFailed(job) {
                    // done before it was ever shown
                    center.dismiss(id)
                }
            }
        }
    }

    private static func hasFailed(_ job: ExtractionJob) -> Bool {
        if case .failed = job.state { return true }
        return false
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(jobs) { job in
                ExtractionProgressRowView(
                    job: job,
                    isExpanded: expandedJobs.contains(job.id),
                    onToggleExpanded: {
                        if expandedJobs.contains(job.id) {
                            expandedJobs.remove(job.id)
                        } else {
                            expandedJobs.insert(job.id)
                        }
                    },
                    onCancel: {
                        center.requestCancel(job.id)
                    },
                    onDismiss: {
                        center.dismiss(job.id)
                    }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                // As the progress window does: a job that is over stays a
                // moment, so the bar is seen complete, then goes — unless it
                // failed, which stays until the user puts it away.
                .task(id: job.isFinished) {
                    guard job.isFinished else { return }
                    if case .failed = job.state { return }
                    do {
                        try await Task.sleep(for: .seconds(1.2))
                    } catch {
                        return
                    }
                    center.dismiss(job.id)
                }

                if job.id != jobs.last?.id {
                    Divider()
                        .padding(.leading, 16)
                }
            }
        }
    }
}
