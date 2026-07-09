//
//  ExtractionProgressView.swift
//  MacPacker
//
//  Created by Claude on 09.07.26.
//

import Charts
import Core
import SwiftUI

/// Content of the extraction progress window: one row per extraction.
/// Collapsed: name, progress bar, byte status, cancel. Expanded: the bar is
/// replaced by a throughput chart whose x-axis spans the whole transfer, so
/// the filled area building up left to right *is* the progress — like the
/// Windows copy dialog.
struct ExtractionProgressView: View {
    @ObservedObject var center: ExtractionProgressCenter
    @State private var expandedJobs: Set<UUID> = []
    @State private var listHeight: CGFloat = 90

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The window follows the content height (dialog grows when
            // details expand, like the Windows copy dialog); the scroll
            // view only kicks in once many parallel extractions run.
            ScrollView {
                VStack(spacing: 0) {
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
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)

                        if job.id != center.jobs.last?.id {
                            Divider()
                                .padding(.leading, 20)
                        }
                    }
                }
                .padding(.top, 2)
                .padding(.bottom, 6)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    listHeight = height
                }
            }
            .frame(height: min(max(listHeight, 80), 480))
        }
        .animation(.easeInOut(duration: 0.15), value: expandedJobs)
        .frame(width: 500)
#if DEBUG
        // screenshot support for the headless e2e hook
        .onChange(of: center.jobs.count) {
            if ProcessInfo.processInfo.environment["MACPACKER_DEBUG_EXPAND"] != nil {
                expandedJobs = Set(center.jobs.map(\.id))
            }
        }
#endif
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
                .symbolEffect(.pulse, options: .repeating, isActive: job.state == .running)
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

                // expanded: the chart replaces the bar — its filled area is
                // the progress indicator
                if isExpanded {
                    ExtractionSpeedChartView(job: job)
                } else {
                    progressBar
                }

                HStack {
                    statusLine
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        onToggleExpanded()
                    } label: {
                        HStack(spacing: 2) {
                            Text("Details", comment: "Toggle in the extraction progress window that shows or hides the speed chart for one extraction.")
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                if isExpanded {
                    expandedStats
                        .padding(.top, 2)
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

    @ViewBuilder
    private var expandedStats: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Average: \(formatSpeed(job.averageBytesPerSecond)) · Items: \(job.itemCount)",
                     comment: "Average speed and item count in the extraction details, e.g. 'Average: 38 MB/s · Items: 12'.")
                    .foregroundStyle(.secondary)

                Spacer()

                if job.state == .running, let remaining = job.estimatedSecondsRemaining {
                    Text("About \(formatDuration(remaining)) remaining",
                         comment: "Time-remaining estimate in the extraction details, e.g. 'About 12 sec remaining'.")
                        .foregroundStyle(.secondary)
                }
            }
            if let destination = job.destination {
                Text(verbatim: destination.path)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(destination.path)
            }
        }
        .font(.caption)
    }
}

/// Speed-over-progress chart: x spans the whole transfer (0…total), so the
/// area builds up left to right and the empty grid on the right is the work
/// still to do — chart and progress bar in one, like the Windows copy
/// dialog. Current speed is overlaid in the plot.
private struct ExtractionSpeedChartView: View {
    let job: ExtractionJob

    /// x position of a sample: transfer fraction when the total is known,
    /// elapsed seconds otherwise.
    private func xValue(_ sample: ExtractionSpeedSample) -> Double {
        if let total = job.totalBytes, total > 0 {
            return min(1.0, Double(sample.completedBytes) / Double(total))
        }
        return sample.elapsed
    }

    private var hasKnownTotal: Bool {
        (job.totalBytes ?? 0) > 0
    }

    var body: some View {
        let base = Chart {
            // progressed part of the transfer gets a tinted background —
            // the boundary between tinted and plain grid is the progress,
            // readable even where the speed line is low
            if hasKnownTotal, let fraction = job.fractionCompleted {
                RectangleMark(
                    xStart: .value("Start", 0.0),
                    xEnd: .value("Progress", fraction)
                )
                .foregroundStyle(Color.accentColor.opacity(0.12))
            }

            ForEach(Array(job.speedSamples.enumerated()), id: \.offset) { _, sample in
                AreaMark(
                    x: .value("Progress", xValue(sample)),
                    y: .value("Speed", sample.bytesPerSecond)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.accentColor.opacity(0.2))

                LineMark(
                    x: .value("Progress", xValue(sample)),
                    y: .value("Speed", sample.bytesPerSecond)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }

            if job.averageBytesPerSecond > 0 {
                RuleMark(y: .value("Average", job.averageBytesPerSecond))
                    .foregroundStyle(.tertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }

        Group {
            if hasKnownTotal {
                base.chartXScale(domain: 0.0...1.0)
            } else {
                base
            }
        }
        .chartYScale(domain: .automatic(includesZero: true))
        .chartXAxis {
            // gridlines only — they make the remaining part of the transfer
            // visible on the right, no labels needed
            if hasKnownTotal {
                AxisMarks(values: [0, 0.25, 0.5, 0.75, 1.0]) { _ in
                    AxisGridLine()
                }
            } else {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine()
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let speed = value.as(Double.self) {
                        // plain "0" instead of byteCount's "Zero kB/s"
                        Text(verbatim: speed > 0 ? formatSpeed(speed) : "0")
                            .font(.system(size: 9))
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            // no plot fill — only the progressed part is tinted (RectangleMark)
            plot
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(.quaternary, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .overlay(alignment: .topTrailing) {
            if job.state == .running {
                Text("Speed: \(formatSpeed(job.currentBytesPerSecond))",
                     comment: "Current speed overlaid on the extraction chart, e.g. 'Speed: 40 MB/s'.")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 4)
                    .padding(.trailing, 44)
            }
        }
        .frame(height: 92)
        .padding(.vertical, 2)
    }
}

// MARK: - Formatting

private func formatBytes(_ bytes: Int64) -> String {
    bytes.formatted(.byteCount(style: .file))
}

private func formatSpeed(_ bytesPerSecond: Double) -> String {
    String(
        format: String(localized: "%@/s", comment: "Extraction speed, e.g. '8 MB/s'. The placeholder is a byte amount."),
        Int64(bytesPerSecond).formatted(.byteCount(style: .file))
    )
}

private func formatDuration(_ seconds: TimeInterval) -> String {
    Duration.seconds(seconds).formatted(
        .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2)
    )
}
