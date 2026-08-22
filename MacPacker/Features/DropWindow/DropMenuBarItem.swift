//
//  DropMenuBarItem.swift
//  MacPacker
//
//  Optional menu bar icon. Off by default; switched on in Settings ▸ General.
//  Its menu mirrors the File menu's window items, wording and all.
//

import AppKit
import Core
import SwiftUI
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "dropwindow")

@MainActor
final class DropMenuBarItem {
    /// The same three actions the File menu offers, so the two cannot drift.
    struct Actions {
        let quickCompress: @MainActor () -> Void
        let openArchive: @MainActor () -> Void
        let newWindow: @MainActor () -> Void
    }

    private var statusItem: NSStatusItem?
    private let actions: Actions

    init(actions: Actions) {
        self.actions = actions
        apply()
        // No token kept for a `deinit` to remove: `deinit` is nonisolated, so
        // reading a non-Sendable property there is a Swift 6 data-race error. This
        // lives as long as the app and the block is weak, so it is inert at worst.
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        }
    }

    private func apply() {
        let wanted = UserDefaults.standard.bool(forKey: Keys.showMenuBarItem)
        guard wanted != (statusItem != nil) else { return }
        if wanted { install() } else { remove() }
    }

    private func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.icon
        item.button?.toolTip = String(localized: "Quick Compress", comment: "Title of the quick-compress window, the small floating window that compresses whatever is dropped on it. Also the title of the compress section on the start page.")
        // Assigning a menu is what makes a click open it; no target/action needed.
        item.menu = makeMenu()
        statusItem = item
        log.notice("Menu bar item installed")
    }

    /// A template image: `isTemplate` lets AppKit recolour the flat black vector,
    /// so it follows light/dark, the click highlight and Reduce Transparency.
    /// 16pt tall in the 22pt bar; width from the artwork's own aspect, never
    /// hardcoded — swapping the asset means changing `artwork` and nothing else.
    /// The asset's viewBox, so the glyph is never stretched.
    private static let artwork = NSSize(width: 15.19, height: 15.19)

    private static let icon: NSImage? = {
        guard let image = NSImage(named: "MenuBarIcon") else { return nil }
        let height: CGFloat = 16
        image.size = NSSize(width: (height * artwork.width / artwork.height).rounded(),
                            height: height)
        image.isTemplate = true
        image.accessibilityDescription = String(localized: "Quick Compress", comment: "Title of the quick-compress window, the small floating window that compresses whatever is dropped on it. Also the title of the compress section on the start page.")
        return image
    }()

    private func remove() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        log.notice("Menu bar item removed")
    }

    /// Same items, wording and order as the File menu — reusing those strings
    /// rather than adding parallel ones to translate.
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(entry(
            String(localized: "New \(Bundle.main.displayName) Window"),
            symbol: "plus.rectangle", action: #selector(newWindow)))
        menu.addItem(entry(
            String(localized: "Quick Compress Window", comment: "Opens the small floating window that compresses whatever is dropped on it. Used in the File menu and in the More menu of the archive window."),
            symbol: "shippingbox", action: #selector(quickCompress)))
        menu.addItem(.separator())
        menu.addItem(entry(
            String(localized: "Open…", comment: "A label for a button that allows the user to open an archive from disk."),
            symbol: "arrow.up.right.square", action: #selector(openArchive)))
        return menu
    }

    private func entry(_ title: String, symbol: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    @objc private func quickCompress() { actions.quickCompress() }
    @objc private func openArchive() { actions.openArchive() }
    @objc private func newWindow() { actions.newWindow() }
}
