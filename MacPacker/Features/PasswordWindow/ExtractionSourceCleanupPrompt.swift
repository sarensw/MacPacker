import AppKit
import Core

@MainActor
enum ExtractionSourceCleanupPrompt {
    /// Checks the current setting so an already-open window honors changes.
    static func request(_ sources: [URL]) -> Bool {
        guard Keys.confirmsTrashAfterExtraction() else { return true }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Move extracted archives to Trash?", comment: "Confirm source cleanup after extraction")
        alert.informativeText = sources.map(\.lastPathComponent).joined(separator: "\n")
        alert.addButton(withTitle: String(localized: "Keep Archives", comment: "Keep source archives after extraction"))
        alert.addButton(withTitle: String(localized: "Move to Trash", comment: "Confirm moving extracted source archives to Trash"))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertSecondButtonReturn
    }
}
