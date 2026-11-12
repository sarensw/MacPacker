//
//  ArchiveTestPanel.swift
//  MacPacker
//

import AppKit

/// "Test Archive" on the start page and in the File menu: asks which archives
/// to test, and hands each to `test`, which puts its verdict up in the progress
/// window. The archive window's toolbar tests the archive it shows instead.
@MainActor
enum ArchiveTestPanel {
    static func run(_ test: @escaping @MainActor (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.begin { response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { @MainActor in urls.forEach(test) }
        }
    }
}
