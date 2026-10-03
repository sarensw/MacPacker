import AppKit
import Core

@MainActor
enum ExtractionConflictPrompt {
    static func request(_ conflict: ExtractionConflict) async -> ExtractionConflictChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Extraction destination already exists", comment: "Title when extracted items conflict with existing files")
        alert.informativeText = conflict.names.prefix(5).joined(separator: "\n") + "\n\n" + String(localized: "Merge keeps existing files and adds missing items. Replace All moves replaced items to Trash. New Folder extracts into a separate numbered folder.", comment: "Explanation of extraction conflict choices")
        alert.addButton(withTitle: String(localized: "Cancel", comment: "Cancel extraction without changing the destination"))
        alert.addButton(withTitle: String(localized: "New Folder", comment: "Extract to a separate uniquely named folder"))
        alert.addButton(withTitle: String(localized: "Merge", comment: "Merge extraction while keeping existing files"))
        alert.addButton(withTitle: String(localized: "Replace All", comment: "Replace conflicting extraction destinations with recoverable backups"))
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertSecondButtonReturn: return .newFolder
        case .alertThirdButtonReturn: return .merge
        case NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + 3): return .replaceAll
        default: return .cancel
        }
    }
}
