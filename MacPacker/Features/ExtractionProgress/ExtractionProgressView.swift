//
//  ExtractionProgressView.swift
//  MacPacker
//
//  Created by Claude on 09.07.26.
//

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

    var body: some View {
        // The window follows the natural content height (the dialog grows
        // when details expand, like the Windows copy dialog). No measured
        // heights and no animation here: animating a layout that drives the
        // window size while chart data ticks every 400 ms wedged SwiftUI
        // mid-transition — the chart froze until the next expand/collapse.
        VStack(alignment: .leading, spacing: 0) {
            if center.jobs.count <= 4 {
                rows
            } else {
                // many parallel extractions: cap the dialog, scroll inside
                ScrollView {
                    rows
                }
                .frame(height: 480)
            }
        }
        .frame(width: 500)
#if DEBUG
        // screenshot support for the headless e2e hook
        .onChange(of: center.jobs.count) {
            if ProcessInfo.processInfo.environment["MACPACKER_DEBUG_EXPAND"] != nil {
                expandedJobs = Set(center.jobs.map(\.id))
            }
        }
        // simulates a user toggling Details mid-run (expand 5s in,
        // collapse at 11s, expand again at 13s)
        .task {
            guard ProcessInfo.processInfo.environment["MACPACKER_DEBUG_EXPAND_CYCLE"] != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            expandedJobs = Set(center.jobs.map(\.id))
            try? await Task.sleep(for: .seconds(6))
            expandedJobs = []
            try? await Task.sleep(for: .seconds(2))
            expandedJobs = Set(center.jobs.map(\.id))
        }
#endif
    }

    @ViewBuilder
    private var rows: some View {
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
                // the progress indicator. The chart itself only re-renders
                // when its (quantized) inputs change; the speed pill sits on
                // top and updates with every report.
                if isExpanded {
                    ExtractionSpeedChartView(
                        samples: job.speedSamples,
                        totalBytes: job.effectiveTotalBytes,
                        fractionCompleted: job.fractionCompleted.map { (($0 * 200).rounded()) / 200 },
                        averageBytesPerSecond: quantized(job.averageBytesPerSecond)
                    )
                    .equatable()
                    .overlay(alignment: .topTrailing) {
                        if job.state == .running {
                            Text("Speed: \(formatSpeed(job.currentBytesPerSecond))",
                                 comment: "Current speed overlaid on the extraction chart, e.g. 'Speed: 40 MB/s'.")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.thinMaterial, in: Capsule())
                                .padding(.top, 6)
                                .padding(.trailing, 60)
                        }
                    }
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
            if let total = job.effectiveTotalBytes {
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

/// Speed-over-progress graph: x spans the whole transfer (0…total), so the
/// line building up left to right and the tinted region are the progress —
/// chart and progress bar in one, like the Windows copy dialog.
///
/// Deliberately NOT Swift Charts: this is a plain `Canvas` — a pure draw
/// function over immutable slot points. No internal state, no display link,
/// no implicit animations, nothing a window capture or occlusion change can
/// wedge; it redraws exactly when SwiftUI invalidates it. Points are drawn
/// raw with straight segments — no smoothing, no normalization, and history
/// never changes shape (the points themselves are append-only).
///
/// Equatable and used via `.equatable()`: reports arrive several times per
/// second, but the drawn inputs only change when a new slot point lands.
/// The live speed pill lives in the row, outside this view.
private struct ExtractionSpeedChartView: View, Equatable {
    /// Append-only slot points from the job.
    let samples: [ExtractionSpeedSample]
    let totalBytes: Int64?
    /// Quantized by the caller so tiny changes don't defeat Equatable.
    let fractionCompleted: Double?
    let averageBytesPerSecond: Double

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.samples == rhs.samples
            && lhs.totalBytes == rhs.totalBytes
            && lhs.fractionCompleted == rhs.fractionCompleted
            && lhs.averageBytesPerSecond == rhs.averageBytesPerSecond
    }

    /// Top of the y scale: a "nice" 1/2/5×10ⁿ value above the data.
    private var yMax: Double {
        let peak = max(samples.map(\.bytesPerSecond).max() ?? 0, averageBytesPerSecond, 1)
        return niceCeil(peak)
    }

    /// x position of a sample in 0…1.
    private func xFraction(_ sample: ExtractionSpeedSample) -> Double {
        if let total = totalBytes, total > 0 {
            return min(1.0, Double(sample.completedBytes) / Double(total))
        }
        // no total: normalize over the observed time range
        guard let last = samples.last, last.elapsed > 0 else { return 0 }
        return sample.elapsed / last.elapsed
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Canvas { context, size in
                let width = size.width
                let height = size.height
                let top = yMax
                func yPosition(_ value: Double) -> CGFloat {
                    height - CGFloat(min(value, top) / top) * height
                }

                // progressed part of the transfer gets a tinted background —
                // the boundary between tinted and plain grid is the
                // progress, readable even where the speed line is low
                if let fraction = fractionCompleted {
                    let tinted = CGRect(x: 0, y: 0, width: width * CGFloat(fraction), height: height)
                    context.fill(Path(tinted), with: .color(.accentColor.opacity(0.12)))
                }

                // grid: quarter verticals, half horizontal
                var grid = Path()
                for fraction in [0.25, 0.5, 0.75] {
                    grid.move(to: CGPoint(x: width * fraction, y: 0))
                    grid.addLine(to: CGPoint(x: width * fraction, y: height))
                }
                grid.move(to: CGPoint(x: 0, y: height / 2))
                grid.addLine(to: CGPoint(x: width, y: height / 2))
                context.stroke(grid, with: .color(.secondary.opacity(0.2)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

                // raw polyline + fill underneath — straight segments only
                if samples.count > 1 {
                    var line = Path()
                    line.move(to: CGPoint(x: CGFloat(xFraction(samples[0])) * width, y: yPosition(samples[0].bytesPerSecond)))
                    for sample in samples.dropFirst() {
                        line.addLine(to: CGPoint(x: CGFloat(xFraction(sample)) * width, y: yPosition(sample.bytesPerSecond)))
                    }

                    var area = line
                    area.addLine(to: CGPoint(x: CGFloat(xFraction(samples[samples.count - 1])) * width, y: height))
                    area.addLine(to: CGPoint(x: CGFloat(xFraction(samples[0])) * width, y: height))
                    area.closeSubpath()

                    context.fill(area, with: .color(.accentColor.opacity(0.2)))
                    context.stroke(line, with: .color(.accentColor), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }

                // dashed average line
                if averageBytesPerSecond > 0 {
                    let averageY = yPosition(averageBytesPerSecond)
                    var average = Path()
                    average.move(to: CGPoint(x: 0, y: averageY))
                    average.addLine(to: CGPoint(x: width, y: averageY))
                    context.stroke(average, with: .color(.secondary.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.quaternary, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // y-axis labels: top, middle, zero
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: formatSpeed(yMax))
                Spacer()
                Text(verbatim: formatSpeed(yMax / 2))
                Spacer()
                Text(verbatim: "0")
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .frame(width: 48, alignment: .leading)
        }
        .frame(height: 92)
        .padding(.vertical, 2)
    }
}

/// Smallest "nice" chart ceiling (1, 2, or 5 times a power of ten) at or
/// above the value.
private func niceCeil(_ value: Double) -> Double {
    guard value > 0 else { return 1 }
    let magnitude = pow(10, floor(log10(value)))
    let normalized = value / magnitude
    let factor: Double = normalized <= 1 ? 1 : normalized <= 2 ? 2 : normalized <= 5 ? 5 : 10
    return factor * magnitude
}

// MARK: - Formatting

/// Rounds to two significant digits — stable enough for Equatable checks,
/// indistinguishable on a 92 pt tall chart.
private func quantized(_ value: Double) -> Double {
    guard value > 0 else { return 0 }
    let magnitude = pow(10, floor(log10(value)) - 1)
    return (value / magnitude).rounded() * magnitude
}

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
