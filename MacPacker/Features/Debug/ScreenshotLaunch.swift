//
//  ScreenshotLaunch.swift
//  MacPacker
//
//  Created by Claude on 13.07.26.
//

#if DEBUG
import AppKit
import Core
import Foundation

/// DEBUG-only: drives the app into a specific, screenshot-ready state from
/// launch parameters. These are generic, app-independent debug parameters — any
/// screenshot tool or test harness (SandboxPilot is one) sets them so the app
/// opens directly into a given state, no UI scripting required.
///
/// Read from `UserDefaults`, so they work both as `NSArgumentDomain`
/// command-line arguments and as launch-time defaults a driver patches before
/// relaunching:
///
///   -ArchivePath  <path>    open this archive in a window
///   -NavigatePath a/b/c     navigate into these tree segments, in order
///   -SelectItem   <name>    select this child of the final folder
///   -ExtractDemo  1         show the extraction window with mock progress
///
/// Language is applied by the system via `-AppleLanguages`; appearance
/// (light/dark) is applied by the driver after launch.
@MainActor
enum ScreenshotLaunch {
    private static let archivePathKey = "ArchivePath"
    private static let navigatePathKey = "NavigatePath"
    private static let selectItemKey = "SelectItem"
    static let extractDemoKey = "ExtractDemo"

    /// True when the app was launched to produce a screenshot. Used to suppress
    /// the welcome window and other launch noise that would clutter the shot.
    static var isActive: Bool {
        let d = UserDefaults.standard
        return d.bool(forKey: extractDemoKey) || d.string(forKey: archivePathKey) != nil
    }

    static func applyIfRequested(windowManager: ArchiveWindowManager) {
        let d = UserDefaults.standard

        if d.bool(forKey: extractDemoKey) {
            showExtractionDemo()
            return
        }

        guard let archivePath = d.string(forKey: archivePathKey) else { return }
        let url = URL(fileURLWithPath: archivePath)
        let navigate = d.string(forKey: navigatePathKey)
        let select = d.string(forKey: selectItemKey)

        let state = windowManager.debugOpenControllableWindow(for: url)
        Task { await drive(state, navigate: navigate, select: select) }
    }

    /// Waits for the initial load, walks the requested path segment by segment
    /// (awaiting each nested-archive unfold), then selects the requested item.
    private static func drive(_ state: ArchiveState, navigate: String?, select: String?) async {
        try? await state.openTask?.value

        if let navigate, !navigate.isEmpty {
            for segment in navigate.split(separator: "/").map(String.init) {
                guard let child = state.childItems?.first(where: { $0.name == segment }) else {
                    NSLog("[ScreenshotLaunch] navigate segment not found: \(segment)")
                    break
                }
                try? await state.openAsync(item: child)
            }
        }

        if let select, !select.isEmpty {
            if let item = state.childItems?.first(where: { $0.name == select }) {
                state.selectedItems = [item]
                state.isReloadNeeded = true
            } else {
                NSLog("[ScreenshotLaunch] select item not found: \(select)")
            }
        }
    }

    /// One running job sitting at 1/3 of a large file, with enough throughput
    /// samples that the details chart draws a visible rising curve. The job is
    /// never finished, so the window stays open for the screenshot.
    private static func showExtractionDemo() {
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
