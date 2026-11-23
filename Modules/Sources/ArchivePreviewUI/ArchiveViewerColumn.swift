//
//  ArchiveViewerColumn.swift
//  MacPacker
//

import AppKit
import Core
import tb

/// The list's columns, in the order the archive window and Quick Look show them.
public enum ArchiveViewerColumn: String, CaseIterable, Sendable {
    case name
    case compressedSize
    case uncompressedSize
    case modificationDate
    case posixPermissions

    public var identifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(self.rawValue)
    }

    public init?(identifier: NSUserInterfaceItemIdentifier) {
        self.init(rawValue: identifier.rawValue)
    }

    /// The setting that shows or hides the column; the name always shows.
    var visibilitySetting: String? {
        switch self {
        case .name: nil
        case .compressedSize: Keys.showColumnCompressedSize
        case .uncompressedSize: Keys.showColumnUncompressedSize
        case .modificationDate: Keys.showColumnModificationDate
        case .posixPermissions: Keys.showColumnPosixPermissions
        }
    }
}

enum PreviewLog {
    static let subsystem = "app.MacPacker"
    static let general = tb.Logger(subsystem: subsystem, category: "quicklook")
    static let drag    = tb.Logger(subsystem: subsystem, category: "quicklook.drag")
}
