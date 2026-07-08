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
    private var scheduledClose: DispatchWorkItem?

    init(center: ExtractionProgressCenter) {
        self.center = center

        let hosting = NSHostingController(rootView: ExtractionProgressView(center: center))
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "Extracting", comment: "Title of the extraction progress window.")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 480, height: 160))
        window.isReleasedWhenClosed = false

        super.init(window: window)
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

            if window?.isVisible != true {
                log.notice("Extraction progress window shown", context: ["jobs": "\(jobs.count)"])
                window?.center()
                showWindow(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            return
        }

        // no active jobs (list may also be empty after clearFinished)
        guard !jobs.isEmpty, window?.isVisible == true, scheduledClose == nil else { return }

        let anyFailed = jobs.contains {
            if case .failed = $0.state { return true }
            return false
        }
        // a failure stays on screen until the user closes the window
        guard !anyFailed else { return }

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

    func windowWillClose(_ notification: Notification) {
        scheduledClose?.cancel()
        scheduledClose = nil
        center.clearFinished()
    }
}
