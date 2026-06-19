//
//  QuickLookHarnessWindowController.swift
//  MacPacker
//
//  Developer harness window that hosts the shared Quick Look preview UI
//  (`ArchivePreviewUI.ArchivePreviewViewController`) in-process, so the exact
//  code that runs inside the QuickLook appex can be exercised with the debugger
//  attached — no appex host, no `qlmanage`. Run MacPacker (⌘R) and open it from
//  Settings ▸ Debug ▸ "Open Quick Look Harness…" (the Debug tab is DEBUG-only).
//

import AppKit
import ArchivePreviewUI

final class QuickLookHarnessWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate {
    private let previewController = ArchivePreviewViewController()

    /// Keeps the controller alive for the window's lifetime (callers use the
    /// `QuickLookHarnessWindowController().show()` idiom without holding a ref).
    private static var retained: QuickLookHarnessWindowController?

    private static let openItemID = NSToolbarItem.Identifier("QuickLookHarness.open")

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Quick Look Harness"
        window.isReleasedWhenClosed = false
        self.init(window: window)

        // Assign the content view controller first: NSWindow resizes itself to
        // the controller's fitting size when this is set, which (with the empty
        // outline view) collapses to the minimum — so set a sensible size after.
        window.contentViewController = previewController
        window.delegate = self
        window.contentMinSize = NSSize(width: 480, height: 320)
        window.setContentSize(NSSize(width: 820, height: 560))
        window.center()

        let toolbar = NSToolbar(identifier: "QuickLookHarnessToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        window.toolbar = toolbar
    }

    /// Shows the harness window (and opens a file picker on first show so the
    /// debug workflow is "open harness → pick archive → step through").
    func show() {
        let firstShow = window?.isVisible == false
        Self.retained = self
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if firstShow { presentOpenPanel() }
    }

    func windowWillClose(_ notification: Notification) {
        Self.retained = nil
    }

    // MARK: - Loading

    @objc private func openArchive(_ sender: Any?) {
        presentOpenPanel()
    }

    private func presentOpenPanel() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an archive to preview"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.load(url)
        }
    }

    private func load(_ url: URL) {
        window?.title = "Quick Look Harness — \(url.lastPathComponent)"
        Task { try? await previewController.loadPreview(of: url) }
    }

    // MARK: - NSToolbarDelegate

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == Self.openItemID else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "Open…"
        item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Open archive")
        item.target = self
        item.action = #selector(openArchive(_:))
        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.openItemID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.openItemID, .flexibleSpace]
    }
}
