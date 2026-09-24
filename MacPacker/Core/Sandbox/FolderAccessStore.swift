//
//  FolderAccessStore.swift
//  MacPacker
//
//  Acquires access to the folder an operation reads from or writes into: the
//  folder holding an archive (so split siblings are readable), the folder a
//  Finder action writes into. This is only the *acquisition* (grant) side —
//  the rule is `Core.FolderAccess`, persistence and the access scope live in
//  `Core.Sandbox`, which the read and write sites bracket with `Sandbox.access`.
//
//  Every folder-access prompt in the app goes through here, so a grant is asked
//  for at most once per folder tree: what the panel returns is persisted as a
//  bookmark, and any stored grant on an ancestor is reused. Settings › Permissions
//  grants the home folder and /Volumes up front, which covers most of it.
//

import AppKit
import Core
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "sandbox")

@MainActor
final class FolderAccessStore {
    static let shared = FolderAccessStore()

    /// The two folders Settings › Permissions offers: one grant each covers
    /// everything the user keeps at home and on every mounted volume.
    static let volumesFolder = URL(fileURLWithPath: "/Volumes", isDirectory: true)

    /// The real (non-container) home. `getpwuid` gives the true home even inside
    /// the sandbox, where `NSHomeDirectory()` returns the container.
    static var homeFolder: URL? {
        guard let pw = getpwuid(getuid()) else { return nil }
        let home = String(cString: pw.pointee.pw_dir)
        return home.isEmpty ? nil : URL(fileURLWithPath: home, isDirectory: true)
    }

    /// The real `~/Downloads` — the folder the `files.downloads.read-write`
    /// entitlement covers.
    ///
    /// The name is spelled out on purpose. On disk the folder is `Downloads` in
    /// every language: what a Japanese Finder shows as ダウンロード is the display
    /// name macOS derives from the `.localized` marker inside it, never the path.
    /// `FileManager.urls(for: .downloadsDirectory…)` would be the tidier call, but
    /// inside the sandbox it answers with the *container's* Downloads, which is
    /// not what the entitlement covers and not where the user's files are.
    static var downloadsFolder: URL? {
        homeFolder?.appendingPathComponent("Downloads", isDirectory: true)
    }

    /// Ensure the folder containing `fileURL` is accessible. Returns false only
    /// if the user declined.
    func ensureAccess(forFileIn fileURL: URL) async -> Bool {
        await ensureAccess(to: fileURL, isDirectory: false)
    }

    /// Ensure `folder` itself is accessible — a Finder action's target folder,
    /// which is where it reads its input and writes its result.
    func ensureAccess(forFolder folder: URL) async -> Bool {
        await ensureAccess(to: folder, isDirectory: true)
    }

    /// Whether a stored grant already covers `folder` — what Settings shows.
    func hasAccess(to folder: URL) -> Bool {
        Sandbox.securityScopedURL(for: folder) != nil
    }

    /// Ask for `folder` outright and persist it: the Permissions buttons, where
    /// the point *is* the grant. Returns false if the user cancelled, or picked
    /// a folder that does not contain the one asked for — the panel lets them
    /// navigate anywhere, and answering it elsewhere leaves the operation
    /// without access. What they picked is kept even then: they did grant it,
    /// and it saves a panel the next time something below it is opened.
    func grantAccess(to folder: URL) async -> Bool {
        guard let granted = await promptForFolder(seed: folder) else { return false }
        Sandbox.storeBookmark(url: granted)
        guard FolderAccess.isInside(folder, granted) else {
            log.error("Granted folder does not cover the one asked for", context: [
                "asked": folder.lastPathComponent, "granted": granted.lastPathComponent
            ])
            return false
        }
        log.info("Folder access granted", context: ["folder": granted.lastPathComponent])
        return true
    }

    private func ensureAccess(to url: URL, isDirectory: Bool) async -> Bool {
        switch FolderAccess.decide(
            for: url,
            isDirectory: isDirectory,
            downloads: Self.downloadsFolder,
            isCovered: { Sandbox.securityScopedURL(for: $0) != nil }
        ) {
        case .covered:
            return true

        // Covered by the entitlement: no panel and no bookmark of ours. macOS
        // still asks once, as the system alert about the Downloads folder, and
        // remembers that answer itself; listing the folder is what triggers it.
        // Detached because that listing blocks for as long as the alert is up,
        // and this runs on the main actor.
        case .downloads(let downloads):
            let path = downloads.path
            let granted = await Task.detached {
                (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
            }.value
            if !granted { log.error("Downloads access declined") }
            return granted

        case .prompt(let folder):
            guard await grantAccess(to: folder) else {
                log.error("Folder access denied", context: ["folder": folder.lastPathComponent])
                return false
            }
            return true
        }
    }

    // MARK: - Prompt

    private func promptForFolder(seed: URL) async -> URL? {
        await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.directoryURL = seed
            panel.prompt = String(localized: .commonGrantAccess)
            panel.message = String(localized: .sandboxAccessNeededMessage(appName: Constants.appName, path: seed.lastPathComponent))
            panel.level = .floating
            NSApp.activate(ignoringOtherApps: true)
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }
}
