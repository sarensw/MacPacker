//
//  ExtractionProgressView.swift
//  MacPacker
//
//  Created by Claude on 09.07.26.
//

import Core
import SwiftUI

/// Content of the extraction progress window: one compact row per running
/// extraction (name, bar, byte status, cancel), expandable into details —
/// same pattern as the Windows copy dialog.
struct ExtractionProgressView: View {
    @ObservedObject var center: ExtractionProgressCenter
    @State private var expandedJobs: Set<UUID> = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(center.jobs) { job in
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
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    if job.id != center.jobs.last?.id {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
        }
        .frame(minWidth: 460, idealWidth: 480, minHeight: 120, idealHeight: 160)
    }
}

private struct ExtractionProgressRowView: View {
    let job: ExtractionJob
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.title2)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(verbatim: job.archiveName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    trailingControl
                }

                progressBar

                HStack {
                    statusLine
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            onToggleExpanded()
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Text("Details", comment: "Toggle in the extraction progress window that shows or hides additional information for one extraction.")
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                if isExpanded {
                    detailsGrid
                        .padding(.top, 4)
                }
            }
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private var trailingControl: some View {
        switch job.state {
        case .running:
            Button(action: onCancel) {
                Image(systemName: "x.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(Text("Cancel extraction", comment: "Tooltip of the button that cancels a running extraction."))
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "slash.circle")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var progressBar: some View {
        switch job.state {
        case .running:
            if let fraction = job.fractionCompleted {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
            } else {
                // total size unknown — keep the bar moving anyway
                ProgressView()
                    .progressViewStyle(.linear)
            }
        case .done:
            ProgressView(value: 1)
                .progressViewStyle(.linear)
        case .failed, .cancelled:
            ProgressView(value: job.fractionCompleted ?? 0)
                .progressViewStyle(.linear)
                .tint(.secondary)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch job.state {
        case .running:
            if let total = job.totalBytes {
                Text("\(formatBytes(job.completedBytes)) of \(formatBytes(total))",
                     comment: "Progress line in the extraction window, e.g. '12 MB of 87 MB'.")
            } else {
                Text("\(formatBytes(job.completedBytes)) extracted…",
                     comment: "Progress line in the extraction window when the total size is unknown.")
            }
        case .done:
            Text("Done", comment: "Status shown in the extraction window when an extraction finished successfully.")
        case .failed(let message):
            Text("Failed: \(message)", comment: "Status shown in the extraction window when an extraction failed. The placeholder is the error message.")
                .foregroundStyle(.red)
                .lineLimit(2)
        case .cancelled:
            Text("Cancelled", comment: "Status shown in the extraction window when an extraction was cancelled by the user.")
        }
    }

    private var detailsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
            if let destination = job.destination {
                GridRow {
                    Text("Destination:", comment: "Label in the extraction details for the target folder.")
                        .gridColumnAlignment(.trailing)
                    Text(verbatim: destination.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(destination.path)
                }
            }
            GridRow {
                Text("Items:", comment: "Label in the extraction details for the number of extracted items.")
                    .gridColumnAlignment(.trailing)
                Text(verbatim: "\(job.itemCount)")
            }
            GridRow {
                Text("Elapsed:", comment: "Label in the extraction details for the elapsed time.")
                    .gridColumnAlignment(.trailing)
                Text(verbatim: elapsedText)
            }
            if job.state == .running, let speed = speedText {
                GridRow {
                    Text("Speed:", comment: "Label in the extraction details for the extraction speed.")
                        .gridColumnAlignment(.trailing)
                    Text(verbatim: speed)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: Formatting

    private func formatBytes(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }

    private var elapsed: TimeInterval {
        (job.finishedAt ?? Date()).timeIntervalSince(job.startedAt)
    }

    private var elapsedText: String {
        Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond))
    }

    /// Average speed; good enough for a dialog that refreshes with every
    /// progress sample.
    private var speedText: String? {
        guard elapsed >= 1, job.completedBytes > 0 else { return nil }
        let perSecond = Int64(Double(job.completedBytes) / elapsed)
        return String(
            format: String(localized: "%@/s", comment: "Extraction speed, e.g. '8 MB/s'. The placeholder is a byte amount."),
            formatBytes(perSecond)
        )
    }
}
