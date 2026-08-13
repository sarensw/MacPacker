//
//  FolderAccessStore.swift
//  MacPacker
//
//  Acquires read access to the folder containing an archive so split /
//  multi-volume siblings are readable under the App Sandbox. This is only the
//  *acquisition* (grant) side — persistence, ancestor-reuse and the access scope
//  itself live in `Core.Sandbox`, which the read sites bracket with
//  `Sandbox.access`.
//
//  Strategy, cheapest first:
//   • already covered by a stored bookmark (this folder or an ancestor) → done.
//   • under ~/Downloads → the `files.downloads.read-write` entitlement gives a
//     one-click system prompt, no panel and no bookmark.
//   • otherwise → prompt (powerbox) for the folder and persist a bookmark via
//     `Sandbox.storeBookmark`. A grant on any ancestor is reused (step 1), so
//     opening more archives under it doesn't re-prompt.
//

import AppKit
import Core
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "sandbox")

@MainActor
final class FolderAccessStore {
    static let shared = FolderAccessStore()

    /// Ensure the folder containing `fileURL` is readable. Returns false only if
    /// the user declined. On success the grant is a persisted bookmark (powerbox)
    /// or the Downloads entitlement — the read sites pick it up via `Sandbox.access`.
    func ensureAccess(forFileIn fileURL: URL) async -> Bool {
        // 1. Already covered by a stored bookmark on this folder or an ancestor.
        if Sandbox.securityScopedURL(for: fileURL) != nil {
            return true
        }

        let folder = fileURL.deletingLastPathComponent()

        // 2. Downloads — covered by the entitlement: a single one-click system
        //    prompt on first use, no panel and no bookmark.
        if let downloads = downloadsFolder(), isUnder(folder, downloads) {
            let path = downloads.path
            let granted = await Task.detached {
                (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
            }.value
            if !granted { log.error("Downloads access declined") }
            return granted
        }

        // 3. Otherwise prompt for this folder and persist the grant.
        guard let granted = await promptForFolder(seed: folder) else {
            log.error("Folder access denied", context: ["folder": folder.lastPathComponent])
            return false
        }
        Sandbox.storeBookmark(url: granted)
        return true
    }

    private func isUnder(_ folder: URL, _ ancestor: URL) -> Bool {
        let f = folder.standardizedFileURL.path
        let a = ancestor.standardizedFileURL.path
        return f == a || f.hasPrefix(a + "/")
    }

    /// The real (non-container) home. `getpwuid` gives the true home even inside
    /// the sandbox, where `NSHomeDirectory()` returns the container.
    private func realHome() -> URL? {
        guard let pw = getpwuid(getuid()) else { return nil }
        let home = String(cString: pw.pointee.pw_dir)
        return home.isEmpty ? nil : URL(fileURLWithPath: home, isDirectory: true)
    }

    private func downloadsFolder() -> URL? {
        realHome()?.appendingPathComponent("Downloads", isDirectory: true)
    }

    // MARK: - Prompt

    private func promptForFolder(seed: URL) async -> URL? {
        await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.directoryURL = seed
            panel.prompt = String(localized: "Grant Access", comment: "Confirmation button in the folder-access panel")
            panel.message = String(localized: "\(Constants.appName) needs access to \(seed.lastPathComponent)", comment: "Message in the file- and folder-access panel explaining why permission is required. The first placeholder is the app name MacPacker, the second is the name of the file or folder that needs access.")
            panel.level = .floating
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }
}
