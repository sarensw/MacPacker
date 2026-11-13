//
//  AccessibilityIdentifiers.swift
//  MacPacker
//

import AppKit

/// Stable names for the windows and controls that something other than a mouse
/// needs to address: VoiceOver, the XCUITests, and the screenshot plan.
///
/// An identifier is not a label. Labels are translated, so anything matching on
/// one breaks in fourteen languages; identifiers never change, which is exactly
/// why automation should target them. They are also invisible to users, so
/// naming one costs nothing.
enum AccessibilityIdentifier {
    /// The toolbar search field that `.searchable` builds in `ContentView`.
    static let searchField = "archive.searchField"

    /// An archive window, which is the start page while it holds no archive.
    static let archiveWindow = "archive.window"
    static let welcomeWindow = "welcome.window"
    /// The floating Quick Compress (drop) window.
    static let quickCompressWindow = "quickCompress.window"
    /// The extraction and compression progress window.
    static let progressWindow = "progress.window"
    /// Settings ▸ General ▸ Show hidden files. Its row label is a separate text,
    /// so the toggle itself has no name to find it by.
    static let showHiddenFilesSetting = "settings.showHiddenFiles"
}

extension NSWindow {
    /// Publishes accessibility identifiers on the controls SwiftUI builds for us.
    ///
    /// SwiftUI has no way to name the field behind `.searchable` — the modifier
    /// takes no identifier and applying one to the view sets it on the container
    /// instead — so the field is reached through the toolbar item that backs it,
    /// the same way ⌘F does in `ArchiveCommands`.
    ///
    /// Safe to call repeatedly: setting the same identifier twice is a no-op, and
    /// the toolbar is empty until SwiftUI has populated it, so early calls simply
    /// find nothing.
    func publishAccessibilityIdentifiers() {
        toolbar?.items
            .lazy
            .compactMap { $0 as? NSSearchToolbarItem }
            .first?
            .searchField
            .setAccessibilityIdentifier(AccessibilityIdentifier.searchField)
    }
}
