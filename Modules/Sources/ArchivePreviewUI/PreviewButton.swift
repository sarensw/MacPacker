//
//  PreviewButton.swift
//  ArchivePreviewUI
//

import AppKit

/// A button that acts on the first click.
///
/// The preview runs in Finder's Quick Look panel, whose window is not key. A
/// plain `NSButton` swallows the first click to activate the window, so the
/// button appears dead — and a second click lands on the panel, which reads a
/// double click as "open this file in its default app" (Archive Utility, for a
/// zip). Accepting the first mouse keeps the click here.
final class PreviewButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
