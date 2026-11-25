//
//  ArchiveListView.swift
//  MacPacker
//
//  The archive window's list: the outline the Quick Look preview shows too,
//  with everything a window may do (#251).
//

import AppKit
import ArchivePreviewUI
import Core
import SwiftUI

struct ArchiveListView: NSViewControllerRepresentable {
    @EnvironmentObject var state: ArchiveState
    @Environment(\.fileDragOverWindow) private var fileDragOverWindow

    // Read here so that a column shown or hidden anywhere reaches the list.
    @AppStorage(Keys.showColumnCompressedSize, store: .macPackerShared) private var showCompressedSize = true
    @AppStorage(Keys.showColumnUncompressedSize, store: .macPackerShared) private var showUncompressedSize = true
    @AppStorage(Keys.showColumnModificationDate, store: .macPackerShared) private var showModificationDate = true
    @AppStorage(Keys.showColumnPosixPermissions, store: .macPackerShared) private var showPermissions = false
    /// Tree or Table, Settings ▸ General (#251 B18).
    @AppStorage(Keys.archiveListStyle) private var listStyle = "tree"

    private var layout: ArchiveOutlineLayout { listStyle == "table" ? .table : .tree }

    func makeCoordinator() -> ContextMenu {
        ContextMenu()
    }

    func makeNSViewController(context: Context) -> ArchiveOutlineController {
        let controller = ArchiveOutlineController(features: .window, layout: layout)
        // the app's own strings: its app tests find the headers by their ids
        controller.columnTitles = [
            .name: String(localized: .columnName),
            .compressedSize: String(localized: .columnPackedSize),
            .uncompressedSize: String(localized: .columnSize),
            .modificationDate: String(localized: .columnDateModified),
            .posixPermissions: String(localized: .columnPermissions),
        ]
        context.coordinator.state = state
        controller.contextMenu = context.coordinator.menu
        controller.state = state
        controller.onFileDrag = fileDragOverWindow
        // the status bar says where a dragged file goes, or why it can't (#251 G2)
        controller.onDropHint = { [weak state] hint in
            guard let state else { return }
            state.dropHint = hint.map { Self.text(for: $0, in: state) }
        }
        return controller
    }

    private static func text(for hint: ArchiveDropHint, in state: ArchiveState) -> String {
        switch hint {
        case .addInto(let names):
            String(localized: .commonAddToNamed(names.isEmpty ? state.name ?? "" : names.joined(separator: " › ")))
        case .cantChange(let name):
            String(localized: .archiveDropCantChange(name))
        case .needsPassword(let name):
            String(localized: .archiveDropNeedsPassword(name))
        case .opening(let name):
            String(localized: .archiveDropOpening(name))
        }
    }

    func updateNSViewController(_ controller: ArchiveOutlineController, context: Context) {
        _ = (showCompressedSize, showUncompressedSize, showModificationDate, showPermissions)
        context.coordinator.state = state
        controller.state = state
        controller.onFileDrag = fileDragOverWindow
        controller.layout = layout
        controller.applyColumnVisibility()
    }

    /// The right-click menu, built anew each time it opens: Open, Quick Look,
    /// Extract, Delete, as 7-Zip and NanaZip offer them. The list has selected
    /// the row clicked by then.
    @MainActor
    final class ContextMenu: NSObject, NSMenuDelegate {
        weak var state: ArchiveState?

        lazy var menu: NSMenu = {
            let menu = NSMenu()
            menu.delegate = self
            menu.autoenablesItems = false
            return menu
        }()

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let state else { return }
            let hasSelection = !state.selectedItems.isEmpty

            let open = NSMenuItem(title: String(localized: .commonOpen), action: #selector(openSelection(_:)), keyEquivalent: "")
            open.image = NSImage(systemSymbolName: "arrow.up.forward.square", accessibilityDescription: nil)
            open.isEnabled = hasSelection
            add(open, to: menu)

            let quickLook = NSMenuItem(title: String(localized: .archiveBrowseQuickLook), action: #selector(quickLook(_:)), keyEquivalent: " ")
            quickLook.keyEquivalentModifierMask = []   // Space, not ⌘Space
            quickLook.image = NSImage(named: "custom.document.badge.eye")
            quickLook.isEnabled = hasSelection
            add(quickLook, to: menu)

            menu.addItem(.separator())

            let extract = NSMenuItem(title: String(localized: .commonExtractSelected), action: #selector(extract(_:)), keyEquivalent: "")
            extract.image = NSImage(named: "custom.document.badge.arrow.down")
            extract.isEnabled = hasSelection
            add(extract, to: menu)

            menu.addItem(.separator())

            let delete = NSMenuItem(title: String(localized: .commonDelete), action: #selector(deleteSelection(_:)), keyEquivalent: "\u{8}")
            delete.keyEquivalentModifierMask = []
            delete.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
            delete.isEnabled = state.canRemove(state.selectedItems)
            add(delete, to: menu)
        }

        private func add(_ item: NSMenuItem, to menu: NSMenu) {
            item.target = self
            menu.addItem(item)
        }

        @objc private func openSelection(_ sender: Any?) {
            guard let state, let item = state.selectedItems.first else { return }
            state.open(item: item)
        }

        @objc private func quickLook(_ sender: Any?) {
            state?.updateSelectedItemForQuickLook()
        }

        @objc private func extract(_ sender: Any?) {
            guard let state else { return }
            let items = state.selectedItems
            guard !items.isEmpty else { return }
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = String(localized: .commonExtract)
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                Task { @MainActor in
                    state.extract(items: items, to: url, smart: Keys.smartExtractionEnabled())
                }
            }
        }

        @objc private func deleteSelection(_ sender: Any?) {
            guard let state, state.canRemove(state.selectedItems) else { return }
            state.remove(items: state.selectedItems)
        }
    }
}
