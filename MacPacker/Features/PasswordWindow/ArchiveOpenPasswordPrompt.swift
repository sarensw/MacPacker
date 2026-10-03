import AppKit
import Core
import SwiftUI

/// Direct extractions have no archive window to attach a password sheet to.
/// Reuse the normal password view in a small, standalone panel instead.
@MainActor
final class ArchiveOpenPasswordPrompt: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var answer: CheckedContinuation<String?, Never>?
    private(set) var wasCancelled = false

    func request(_ request: ArchivePasswordRequest) async -> String? {
        await withCheckedContinuation { continuation in
            answer = continuation
            let content = PasswordView(
                request: request,
                onSubmit: { [weak self] in self?.finish($0) },
                onCancel: { [weak self] in self?.finish(nil) }
            ).frame(width: 380)
            let panel = NSPanel(contentViewController: NSHostingController(rootView: content))
            panel.title = String(localized: .commonPassword)
            panel.styleMask = [.titled, .closable]
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.delegate = self
            panel.center()
            self.panel = panel
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func finish(_ password: String?) {
        guard let continuation = answer else { return }
        answer = nil
        wasCancelled = password == nil
        panel?.delegate = nil
        panel?.close()
        panel = nil
        continuation.resume(returning: password)
    }

    func windowWillClose(_ notification: Notification) {
        finish(nil)
    }
}
