//
//  ExtractedItems.swift
//  Modules
//
//  What an extraction put in the folder it extracted to — for selecting it in
//  Finder once it is done, when that takes no extra window.
//

import AppKit

public enum ExtractedItems {
    /// What is in `folder` now, for comparing with what is there afterwards.
    /// Hidden files are left out: Finder may write its `.DS_Store` there
    /// meanwhile, and that is not for selecting.
    public static func contents(of folder: URL) -> Set<URL> {
        Set((try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
    }

    /// What an extraction put in `folder`: what is there now and was not
    /// `before` — or, where it went over what was there and nothing is new,
    /// the items of those `names` that are there.
    ///
    /// By comparing rather than by predicting names, so it stays right however
    /// the extraction names what it creates — a smart extraction's folder, a
    /// name kept beside one that was taken.
    public static func find(in folder: URL, before: Set<URL>, names: [String]) -> [URL] {
        let added = contents(of: folder).subtracting(before)
        if !added.isEmpty {
            return added.sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        // hidden ones left out here too, as from `contents(of:)`
        return names
            .filter { !$0.hasPrefix(".") }
            .map { folder.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Selects `items` in Finder — but only when Finder has no window open.
    ///
    /// Finder reuses a window for this only when that window's own folder is
    /// theirs: one showing their folder as a subfolder in list view, or any
    /// other, gets a second window next to it. So with a Finder window open,
    /// nothing is opened: what was extracted shows up there by itself whenever
    /// that window shows its folder. With none open, a window opens on them.
    @MainActor
    public static func select(_ items: [URL]) {
        guard !items.isEmpty, !finderHasWindowOpen() else { return }
        NSWorkspace.shared.activateFileViewerSelecting(items)
    }

    /// Whether Finder has a window on screen: one at the normal window level
    /// and of a window's size — not its desktop, nor the small windows it keeps
    /// off screen. Read from the window list, which needs no permission.
    @MainActor
    static func finderHasWindowOpen() -> Bool {
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        return windows.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == finder.processIdentifier,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? CGFloat, let height = bounds["Height"] as? CGFloat
            else { return false }
            return width >= 200 && height >= 100
        }
    }
}
