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
    private var scheduledShow: DispatchWorkItem?
    private var scheduledClose: DispatchWorkItem?

    init(center: ExtractionProgressCenter) {
        self.center = center

        let hosting = NSHostingController(rootView: ExtractionProgressView(center: center))
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "Extracting", comment: "Title of the extraction progress window.")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 480, height: 160))
        window.isReleasedWhenClosed = false
        if !window.setFrameUsingName("ExtractionProgress") {
            window.center()
        }

        super.init(window: window)
        windowFrameAutosaveName = "ExtractionProgress"
        window.delegate = self

        jobsSubscription = center.$jobs
            .receive(on: RunLoop.main)
            .sink { [weak self] jobs in
                self?.jobsChanged(jobs)
            }
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
