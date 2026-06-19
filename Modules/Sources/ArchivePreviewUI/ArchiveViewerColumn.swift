//
//  ArchiveViewerColumn.swift
//  ArchivePreviewUI
//
//  Column identifiers + logging for the shared archive preview UI.
//

import AppKit
import tb

/// Column identifiers for the archive preview's outline view.
enum ArchiveViewerColumn: String, CaseIterable {
    case name
    case compressedSize
    case uncompressedSize
    case modificationDate
    case posixPermissions

    var identifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(self.rawValue)
    }

    init?(identifier: NSUserInterfaceItemIdentifier) {
        self.init(rawValue: identifier.rawValue)
    }
}

/// Logging for the shared preview UI. Uses the same `app.MacPacker` subsystem as
/// the rest of the app so entries line up in Console / the TailBeat viewer,
/// whether the UI runs inside the QuickLook appex or the in-app debug harness.
enum PreviewLog {
    static let subsystem = "app.MacPacker"
    static let general = tb.Logger(subsystem: subsystem, category: "quicklook")
    static let drag    = tb.Logger(subsystem: subsystem, category: "quicklook.drag")
}
