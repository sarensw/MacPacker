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
        .onAppear {
            // The demo job is created before this view appears, so onChange
            // never fires for it — expand on appear too.
            if ExtractionDemo.isRequested {
                expandedJobs = Set(center.jobs.map(\.id))
            }
        }
        .onChange(of: center.jobs.count) {
            if ProcessInfo.processInfo.environment["MACPACKER_DEBUG_EXPAND"] != nil
                || ExtractionDemo.isRequested {
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

/// Fades newly inserted content in without animating layout: the window's
/// height is driven by the content size (preferredContentSize), and
/// animating a size-driving layout change makes AppKit's constraint pass
/// re-query SwiftUI mid-animation until it trips the update-pass limit
/// (NSGenericException, crash under Xcode). Opacity is invisible to layout.
private struct FadeInOnAppear: ViewModifier {
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 0.25)) {
                    shown = true
                }
            }
    }
}

private struct ExtractionProgressRowView: View {
    let job: ExtractionJob
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let onCancel: () -> Void

    var body: some View {
        // collapsed: everything vertically centered on the badge line;
        // expanded: header on line with the controls, details fade in
        HStack(alignment: isExpanded ? .top : .center, spacing: 12) {
            typeBadge

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(verbatim: job.archiveName)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    bytesText

                    trailingControl

                    if job.hasEngineProgress {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if isExpanded, job.hasEngineProgress {
                    Group {
                        ExtractionSpeedChartView(
                            samples: job.speedSamples,
                            totalBytes: job.effectiveTotalBytes,
                            fractionCompleted: job.fractionCompleted.map { (($0 * 200).rounded()) / 200 },
                            averageBytesPerSecond: quantized(job.averageBytesPerSecond)
                        )
                        .equatable()

                        HStack {
                            if job.state == .running {
                                Text(verbatim: formatSpeed(job.currentBytesPerSecond))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if job.state == .running, let remaining = job.estimatedSecondsRemaining {
                                Text("\(formatDuration(remaining)) left",
                                     comment: "Time remaining in the extraction row, e.g. '14 sec left'.")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .font(.caption)
                    }
                    .modifier(FadeInOnAppear())
                } else if !isExpanded {
                    HStack(spacing: 10) {
                        if case .failed(let message) = job.state {
                            Text(verbatim: message)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } else if let fraction = job.fractionCompleted {
                            bar(value: fraction)
                        } else if job.state == .running {
                            bar(value: nil)
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if job.hasEngineProgress {
                onToggleExpanded()
            }
        }
    }

    // MARK: Pieces

    private var typeBadge: some View {
        Text(verbatim: String((job.archiveName as NSString).pathExtension.uppercased().prefix(4)))
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .frame(width: 40, height: 40)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var bytesText: some View {
        if let total = job.effectiveTotalBytes {
            Text(verbatim: "\(formatBytes(job.completedBytes)) / \(formatBytes(total))")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
    }

    @ViewBuilder
    private func bar(value: Double?) -> some View {
        if let value {
            ProgressView(value: value)
                .progressViewStyle(.linear)
                .tint(job.isFinished ? .secondary : Color.accentColor)
        } else {
            ProgressView()
                .progressViewStyle(.linear)
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch job.state {
        case .running:
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
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

// "/s" stays literal in every locale — deliberately not localized
private func formatSpeed(_ bytesPerSecond: Double) -> String {
    "\(Int64(bytesPerSecond).formatted(.byteCount(style: .file)))/s"
}

private func formatDuration(_ seconds: TimeInterval) -> String {
    Duration.seconds(seconds).formatted(
        .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2)
    )
}
