//
//  ExtractionProgressView.swift
//  MacPacker
//
//  Created by Claude on 09.07.26.
//

import Charts
import Core
import SwiftUI

/// Content of the extraction progress window: one card per extraction.
/// Collapsed: name, progress bar, byte status, cancel. Expanded: a
/// throughput chart with current/average speed and a time-remaining
/// estimate — same idea as the Windows copy dialog.
struct ExtractionProgressView: View {
    @ObservedObject var center: ExtractionProgressCenter
    @State private var expandedJobs: Set<UUID> = []
    @State private var listHeight: CGFloat = 90

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
                .padding(.horizontal, 20)
                // room for the traffic lights of the hidden title bar
                .padding(.top, 30)

            // The window follows the content height (dialog grows when
            // details expand, like the Windows copy dialog); the scroll
            // view only kicks in once many parallel extractions run.
            ScrollView {
                VStack(spacing: 10) {
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
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    listHeight = height
                }
            }
            .frame(height: min(max(listHeight, 90), 480))
        }
        .animation(.easeInOut(duration: 0.15), value: expandedJobs)
        .frame(width: 500)
        .background(.ultraThinMaterial)
#if DEBUG
        // screenshot support for the headless e2e hook
        .onChange(of: center.jobs.count) {
            if ProcessInfo.processInfo.environment["MACPACKER_DEBUG_EXPAND"] != nil {
                expandedJobs = Set(center.jobs.map(\.id))
            }
        }
#endif
    }

    private var runningCount: Int {
        center.jobs.count { !$0.isFinished }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Extracting", comment: "Headline of the extraction progress window.")
                .font(.title3.weight(.semibold))
            if runningCount > 0 {
                Text("\(runningCount) in progress", comment: "Subtitle of the extraction progress window; placeholder is the number of running extractions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Finished", comment: "Subtitle of the extraction progress window when no extraction is running anymore.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Rounded card behind each extraction: Liquid Glass on macOS 26+,
/// a regular material with a hairline on macOS 14/15.
private struct CardSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.quaternary, lineWidth: 1)
                )
        }
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

                progressBar

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
                    ExtractionSpeedChartView(job: job)
                        .padding(.top, 6)
                }
            }
        }
        .padding(12)
        .modifier(CardSurface())
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
}

/// Windows-copy-dialog-style details: throughput area chart over the whole
/// run, dashed average line, plus current/average speed and time remaining.
private struct ExtractionSpeedChartView: View {
    let job: ExtractionJob

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            chart

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Speed: \(formatSpeed(job.currentBytesPerSecond))",
                         comment: "Current extraction speed below the chart, e.g. 'Speed: 40 MB/s'.")
                    Text("Average: \(formatSpeed(job.averageBytesPerSecond))",
                         comment: "Average extraction speed below the chart, e.g. 'Average: 38 MB/s'.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if job.state == .running, let remaining = job.estimatedSecondsRemaining {
                        Text("About \(formatDuration(remaining)) remaining",
                             comment: "Time-remaining estimate below the chart, e.g. 'About 12 sec remaining'.")
                    }
                    Text("Items: \(job.itemCount)", comment: "Number of items of this extraction, shown below the chart.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            if let destination = job.destination {
                Text(verbatim: destination.path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(destination.path)
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
        Chart {
            ForEach(Array(job.speedSamples.enumerated()), id: \.offset) { _, sample in
                AreaMark(
                    x: .value("Time", sample.elapsed),
                    y: .value("Speed", sample.bytesPerSecond)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    .linearGradient(
                        colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Time", sample.elapsed),
                    y: .value("Speed", sample.bytesPerSecond)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }

            if job.averageBytesPerSecond > 0 {
                RuleMark(y: .value("Average", job.averageBytesPerSecond))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXAxis(.hidden)
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
        .chartYScale(domain: .automatic(includesZero: true))
        .frame(height: 88)
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
