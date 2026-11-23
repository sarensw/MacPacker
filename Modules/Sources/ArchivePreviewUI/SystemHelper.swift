//
//  SystemHelper.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 28.07.25.
//

import AppKit
import UniformTypeIdentifiers

/// Stateless icon helpers. `Sendable` (no stored state) so the `shared`
/// singleton is usable from the package's Swift 6 concurrency model. Sizes,
/// dates and permissions are written by `EntryText` in Core, which the window
/// shares.
final class SystemHelper: Sendable {
    public static let shared = SystemHelper()

    private init() {}

    func getNSImageByExtension(fileName: String) -> NSImage? {
        let fileExtension = (fileName as NSString).pathExtension
        let icon = NSWorkspace.shared.icon(forFileType: fileExtension)
        return icon
    }

    func getNSImageForFolder() -> NSImage {
        return NSWorkspace.shared.icon(for: .folder)
    }
}
