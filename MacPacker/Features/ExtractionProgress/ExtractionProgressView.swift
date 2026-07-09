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
        .frame(width: 640)
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

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: job.archiveName)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if isExpanded, job.state == .running {
                        Text("Extracting \(job.itemCount) items",
                             comment: "Caption under the archive name in the extraction window; the placeholder is the number of items being extracted.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                metricsLine

                if isExpanded {
                    if job.hasEngineProgress {
                        ExtractionSpeedChartView(
                            samples: job.speedSamples,
                            totalBytes: job.effectiveTotalBytes,
                            fractionCompleted: job.fractionCompleted.map { (($0 * 200).rounded()) / 200 },
                            averageBytesPerSecond: quantized(job.averageBytesPerSecond)
                        )
                        .equatable()
                    } else if job.state == .running {
                        Text("Live progress is not available for this archive type.",
                             comment: "Info text in the extraction details when the extraction engine cannot report progress.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    metadataRow
                        .padding(.top, 2)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onToggleExpanded()
        }
    }

    // MARK: Pieces

    /// One aligned line per row: percentage, bar, bytes, speed, ETA, cancel —
    /// fixed column widths so parallel extractions line up.
    @ViewBuilder
    private var metricsLine: some View {
        HStack(spacing: 12) {
            switch job.state {
            case .running, .done:
                if let fraction = job.fractionCompleted {
                    Text(verbatim: fraction.formatted(.percent.precision(.fractionLength(0))))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .monospacedDigit()
                        .frame(width: 52, alignment: .leading)

                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: .infinity)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(maxWidth: .infinity)
                }

                if job.hasEngineProgress || job.isFinished, let total = job.effectiveTotalBytes {
                    Text(verbatim: "\(formatBytes(job.completedBytes)) / \(formatBytes(total))")
                        .frame(width: 128, alignment: .trailing)
                }

                if job.state == .running, job.hasEngineProgress {
                    Text(verbatim: formatSpeed(job.currentBytesPerSecond))
                        .frame(width: 76, alignment: .trailing)

                    Group {
                        if let remaining = job.estimatedSecondsRemaining {
                            Text("About \(formatDuration(remaining))",
                                 comment: "Time-remaining estimate in the extraction row, e.g. 'About 14 sec'.")
                        } else {
                            Text(verbatim: "")
                        }
                    }
                    .frame(width: 96, alignment: .trailing)
                }

            case .failed(let message):
                Text("Failed: \(message)", comment: "Status shown in the extraction window when an extraction failed. The placeholder is the error message.")
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

            case .cancelled:
                Text("Cancelled", comment: "Status shown in the extraction window when an extraction was cancelled by the user.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            trailingControl
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// Expanded footer, Windows-copy-dialog style: icon + label + value
    /// blocks, with the Details toggle at the trailing edge.
    @ViewBuilder
    private var metadataRow: some View {
        HStack(alignment: .top, spacing: 20) {
            if let destination = job.destination {
                metadataItem(icon: "folder", title: Text("Destination", comment: "Label in the extraction details for the target folder.")) {
                    Text(verbatim: destination.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(destination.path)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer()
            }

            if job.state == .running, job.hasEngineProgress {
                metadataItem(icon: "speedometer", title: Text("Current speed", comment: "Label in the extraction details for the current speed.")) {
                    Text(verbatim: formatSpeed(job.currentBytesPerSecond))
                }

                metadataItem(icon: "chart.bar", title: Text("Average speed", comment: "Label in the extraction details for the average speed.")) {
                    Text(verbatim: formatSpeed(job.averageBytesPerSecond))
                }
            }

            metadataItem(icon: "clock", title: Text("Elapsed time", comment: "Label in the extraction details for the elapsed time.")) {
                Text(verbatim: elapsedText)
            }

            Button {
                onToggleExpanded()
            } label: {
                HStack(spacing: 2) {
                    Text("Details", comment: "Toggle in the extraction progress window that shows or hides the details of one extraction.")
                    Image(systemName: "chevron.up")
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .font(.caption)
    }

    private func metadataItem(icon: String, title: Text, @ViewBuilder value: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                title
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                value()
            }
        }
    }

    private var elapsedText: String {
        let elapsed = (job.finishedAt ?? Date()).timeIntervalSince(job.startedAt)
        return Duration.seconds(elapsed).formatted(.time(pattern: .hourMinuteSecond))
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch job.state {
        case .running:
            Button(action: onCancel) {
                Image(systemName: "x.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.body)
            }
            .buttonStyle(.plain)
            .help(Text("Cancel extraction", comment: "Tooltip of the button that cancels a running extraction."))
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.body)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.body)
        case .cancelled:
            Image(systemName: "slash.circle")
                .foregroundStyle(.secondary)
                .font(.body)
        }
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

                // the data stays raw and immutable — only the DRAWING
                // interpolates: a monotone cubic through the points (same
                // look as Swift Charts' .monotone, no overshoot on spikes)
                if samples.count > 1 {
                    let points = samples.map { sample in
                        CGPoint(x: CGFloat(xFraction(sample)) * width, y: yPosition(sample.bytesPerSecond))
                    }
                    let line = monotoneCurve(through: points)

                    var area = line
                    area.addLine(to: CGPoint(x: points[points.count - 1].x, y: height))
                    area.addLine(to: CGPoint(x: points[0].x, y: height))
                    area.closeSubpath()

                    context.fill(area, with: .color(.accentColor.opacity(0.2)))
                    context.stroke(line, with: .color(.accentColor), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
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

/// Monotone cubic interpolation (Fritsch–Carlson) through points with
/// strictly increasing x: smooth like Swift Charts' `.monotone`, and never
/// overshoots above or below the actual data between two points.
private func monotoneCurve(through rawPoints: [CGPoint]) -> Path {
    // collapse duplicate x positions (keep the newest point)
    var points: [CGPoint] = []
    for point in rawPoints {
        if let last = points.last, point.x - last.x < 0.01 {
            points[points.count - 1] = point
        } else {
            points.append(point)
        }
    }

    var path = Path()
    guard let first = points.first else { return path }
    path.move(to: first)
    guard points.count > 2 else {
        points.dropFirst().forEach { path.addLine(to: $0) }
        return path
    }

    let n = points.count
    var slopes = [CGFloat](repeating: 0, count: n)
    var secants = [CGFloat](repeating: 0, count: n - 1)
    for i in 0..<(n - 1) {
        secants[i] = (points[i + 1].y - points[i].y) / (points[i + 1].x - points[i].x)
    }
    slopes[0] = secants[0]
    slopes[n - 1] = secants[n - 2]
    for i in 1..<(n - 1) {
        // opposite-sign or flat secants force a horizontal tangent — this
        // is what prevents overshoot at local peaks
        slopes[i] = secants[i - 1] * secants[i] <= 0 ? 0 : (secants[i - 1] + secants[i]) / 2
    }
    for i in 0..<(n - 1) where secants[i] != 0 {
        let a = slopes[i] / secants[i]
        let b = slopes[i + 1] / secants[i]
        let h = (a * a + b * b).squareRoot()
        if h > 3 {
            slopes[i] = 3 * secants[i] * a / h
            slopes[i + 1] = 3 * secants[i] * b / h
        }
    }

    for i in 0..<(n - 1) {
        let dx = (points[i + 1].x - points[i].x) / 3
        path.addCurve(
            to: points[i + 1],
            control1: CGPoint(x: points[i].x + dx, y: points[i].y + slopes[i] * dx),
            control2: CGPoint(x: points[i + 1].x - dx, y: points[i + 1].y - slopes[i + 1] * dx)
        )
    }
    return path
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
