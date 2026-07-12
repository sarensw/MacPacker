//
//  ExtractionProgressWindowController.swift
//  MacPacker
//
//  Created by Claude on 09.07.26.
//

import AppKit
import Combine
import Core
import SwiftUI
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "extraction")

/// Owns the extraction progress window. It observes the shared
/// `ExtractionProgressCenter` and
/// - shows itself as soon as a job is running (also for window-less flows
///   like the Finder extension's "Extract here"),
/// - closes itself shortly after all jobs finished successfully,
/// - stays open when a job failed so the error remains visible.
@MainActor
final class ExtractionProgressWindowController: NSWindowController, NSWindowDelegate {
    private let center: ExtractionProgressCenter
    private var jobsSubscription: AnyCancellable?
    private var sizeSubscription: AnyCancellable?
    private var scheduledShow: DispatchWorkItem?
    private var scheduledClose: DispatchWorkItem?

    init(center: ExtractionProgressCenter) {
        self.center = center

        // The window follows the SwiftUI content's height (dialog grows when
        // details expand), but we drive that ourselves via `setContentSize`
        // instead of `sizingOptions = .preferredContentSize`. AppKit re-reads
        // `preferredContentSize` *inside* the window's constraint-update pass,
        // and SwiftUI's measurement re-invalidates constraints from there —
        // a re-entrant `_postWindowNeedsUpdateConstraints` that throws and
        // crashes the app while progress ticks arrive. Measuring in SwiftUI
        // and applying the size on the next runloop turn keeps the resize out
        // of the constraint pass entirely.
        let sizeRelay = PassthroughSubject<CGSize, Never>()
        let hosting = NSHostingController(
            rootView: ExtractionProgressView(center: center)
                .modifier(ContentSizeReader { sizeRelay.send($0) })
        )
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        // accessibility/Mission-Control name only — the visible title bar is
        // compact: traffic lights, no text
        window.title = String(localized: "Extracting", comment: "Title of the extraction progress window.")
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        // provisional size until the first measurement lands (before the
        // 0.6s show delay fires, so the user never sees this size)
        window.setContentSize(NSSize(width: 640, height: 180))
        window.center()

        super.init(window: window)
        window.delegate = self

        sizeSubscription = sizeRelay
            .removeDuplicates()
            // next runloop turn: apply the resize between constraint passes,
            // never inside one
            .receive(on: RunLoop.main)
            .sink { [weak self] size in
                self?.applyContentSize(size)
            }

        jobsSubscription = center.$jobs
            .receive(on: RunLoop.main)
            .sink { [weak self] jobs in
                self?.jobsChanged(jobs)
            }
    }

    /// Resizes the window to the content's measured height, keeping the top
    /// edge fixed so the dialog grows downward when details expand. Runs off
    /// the constraint pass (see the sizing note in `init`).
    private func applyContentSize(_ size: CGSize) {
        guard let window, size.width > 0, size.height > 0 else { return }
        let target = NSSize(width: size.width, height: size.height)
        let current = window.contentRect(forFrameRect: window.frame).size
        guard abs(current.width - target.width) > 0.5 || abs(current.height - target.height) > 0.5 else { return }

        let newFrameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: target)).size
        var frame = window.frame
        let topEdge = frame.maxY
        frame.size = newFrameSize
        frame.origin.y = topEdge - newFrameSize.height
        window.setFrame(frame, display: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func jobsChanged(_ jobs: [ExtractionJob]) {
        let hasActive = jobs.contains { !$0.isFinished }


        if hasActive {
            scheduledClose?.cancel()
            scheduledClose = nil
            scheduleShowIfNeeded()
            return
        }

        scheduledShow?.cancel()
        scheduledShow = nil

        // list may also be empty after clearFinished
        guard !jobs.isEmpty else { return }

        let anyFailed = jobs.contains {
            if case .failed = $0.state { return true }
            return false
        }
        if anyFailed {
            // an error must be seen — show even if the job died before the
            // show delay, and never auto-close
            if window?.isVisible != true {
                presentWindow(reason: "failure")
            }
            return
        }

        guard window?.isVisible == true else {
            // finished before the show delay fired — never flash the window
            center.clearFinished()
            return
        }
        guard scheduledClose == nil else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.scheduledClose = nil
            log.notice("Extraction progress window closing (all jobs finished)")
            self.close()
        }
        scheduledClose = work
        // short linger so the user sees the bar complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    /// Waits briefly before showing so short extractions (small drag-outs,
    /// tiny archives) finish without a window flashing up — same behavior
    /// as the Windows copy dialog.
    private func scheduleShowIfNeeded() {
        guard window?.isVisible != true, scheduledShow == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.scheduledShow = nil
            guard self.center.hasActiveJobs else { return }
            self.presentWindow(reason: "active jobs")
        }
        scheduledShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func presentWindow(reason: String) {
        log.notice("Extraction progress window shown", context: ["reason": reason, "jobs": "\(center.jobs.count)"])
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        scheduledClose?.cancel()
        scheduledClose = nil
        center.clearFinished()
    }
}

/// Reports the content's ideal size to the window controller. `fixedSize`
/// makes the content lay out at its natural height regardless of the height
/// the window currently has, so the measurement is the *ideal* height and
/// never feeds back on the window's own size — no measure/resize loop.
private struct ContentSizeReader: ViewModifier {
    let onChange: (CGSize) -> Void

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onChange(of: proxy.size, initial: true) { _, size in
                            onChange(size)
                        }
                }
            )
    }
}
