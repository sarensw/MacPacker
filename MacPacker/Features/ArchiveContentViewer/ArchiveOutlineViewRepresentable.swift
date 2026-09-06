//
//  ArchiveOutlineViewRepresentable.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 06.09.26.
//

import AppKit
import Cocoa
import Core
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "archive")

struct ArchiveOutlineViewRepresentable: NSViewRepresentable {
    @AppStorage(Keys.defaultOrderColumn) private var defaultOrderColumn: ArchiveSortOrder = ArchiveSortOrder.name
    @AppStorage(Keys.defaultOrderColumnAscending) private var defaultOrderColumnAscending: Bool = true

    @Binding var selection: IndexSet?
    @Binding var isReloadNeeded: Bool
    @EnvironmentObject var archiveState: ArchiveState

    @Binding var showCompressedSizeColumn: Bool
    @Binding var showUncompressedSizeColumn: Bool
    @Binding var showModificationDateColumn: Bool
    @Binding var showPosixPermissionsColumn: Bool

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, @MainActor NSOutlineViewDelegate, NSOutlineViewDataSource, @MainActor NSFilePromiseProviderDelegate, @MainActor NSMenuDelegate {
        var parent: ArchiveOutlineViewRepresentable
        weak var outlineView: ArchiveOutlineView?
        weak var contextOutlineView: NSOutlineView?

        var filePromiseQueue: OperationQueue = {
            let queue = OperationQueue()
            return queue
        }()

        init(_ parent: ArchiveOutlineViewRepresentable) {
            self.parent = parent
        }

        private var childrenCache: [UUID: [ArchiveItem]] = [:]

        func invalidateChildrenCache() {
            childrenCache.removeAll()
        }

        func resolvedChildren(of item: Any?) -> [ArchiveItem] {
            let state = parent.archiveState
            guard let node = (item as? ArchiveItem) ?? state.root else { return [] }
            if let cached = childrenCache[node.id] {
                return cached
            }
            guard let childIDs = node.children else { return [] }
            let items = childIDs.compactMap { state.entries[$0] }
            let sorted = state.sortedForDisplay(items)
            childrenCache[node.id] = sorted
            return sorted
        }

        // MARK: NSOutlineViewDataSource

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            resolvedChildren(of: item).count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            resolvedChildren(of: item)[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            !resolvedChildren(of: item).isEmpty
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
        ) {
            guard let sortDescriptors = outlineView.sortDescriptors.first,
                  let key = sortDescriptors.key,
                  let order = ArchiveSortOrder(rawValue: key) else { return }

            parent.defaultOrderColumn = order
            parent.defaultOrderColumnAscending = sortDescriptors.ascending

            invalidateChildrenCache()
            outlineView.reloadData()
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            pasteboardWriterForItem item: Any
        ) -> (any NSPasteboardWriting)? {
            guard let archiveItem = item as? ArchiveItem else { return nil }
            if archiveItem.type == .unknown || archiveItem.type == .root { return nil }

            let typeId = (archiveItem.ext.isEmpty
                ? UTType.data
                : UTType(filenameExtension: archiveItem.ext))?.identifier
                ?? UTType.data.identifier

            let provider = NSFilePromiseProvider(fileType: typeId, delegate: self)
            provider.userInfo = archiveItem
            return provider
        }

        // MARK: NSOutlineViewDelegate

        func outlineView(
            _ outlineView: NSOutlineView,
            userCanChangeVisibilityOf column: NSTableColumn
        ) -> Bool {
            column.identifier != ArchiveViewerColumn.name.identifier
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            userDidChangeVisibilityOf columns: [NSTableColumn]
        ) {
            for column in columns {
                guard let col = ArchiveViewerColumn(identifier: column.identifier) else { continue }
                switch col {
                case .compressedSize:
                    parent.showCompressedSizeColumn = !column.isHidden
                case .name:
                    continue
                case .uncompressedSize:
                    parent.showUncompressedSizeColumn = !column.isHidden
                case .modificationDate:
                    parent.showModificationDateColumn = !column.isHidden
                case .posixPermissions:
                    parent.showPosixPermissionsColumn = !column.isHidden
                }
            }
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            viewFor tableColumn: NSTableColumn?,
            item: Any
        ) -> NSView? {
            guard let columnIdentifier = tableColumn?.identifier,
                  let archiveItem = item as? ArchiveItem else { return nil }

            let cellView = NSTableCellView()
            cellView.identifier = columnIdentifier

            switch columnIdentifier {
            case ArchiveViewerColumn.name.identifier:
                let iconView = NSImageView()
                iconView.translatesAutoresizingMaskIntoConstraints = false
                iconView.imageScaling = .scaleProportionallyDown
                iconView.setContentHuggingPriority(.required, for: .horizontal)
                iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

                let icon: NSImage
                if let cached = archiveItem.icon {
                    icon = cached
                } else {
                    let computed: NSImage
                    if archiveItem.isFolder {
                        computed = NSWorkspace.shared.icon(for: .folder)
                    } else {
                        computed = NSWorkspace.shared.icon(forFileType: archiveItem.ext)
                    }
                    archiveItem.icon = computed
                    icon = computed
                }
                icon.size = NSSize(width: 16, height: 16)
                iconView.image = icon

                let label = NSTextField(labelWithString: archiveItem.name)
                label.translatesAutoresizingMaskIntoConstraints = false
                label.usesSingleLineMode = true
                label.lineBreakMode = .byTruncatingTail

                cellView.imageView = iconView
                cellView.textField = label

                cellView.addSubview(iconView)
                cellView.addSubview(label)

                NSLayoutConstraint.activate([
                    iconView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 2),
                    iconView.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                    iconView.widthAnchor.constraint(equalToConstant: 16),
                    iconView.heightAnchor.constraint(equalToConstant: 16),

                    label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 5),
                    label.trailingAnchor.constraint(equalTo: cellView.trailingAnchor),
                    label.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
                ])

            case ArchiveViewerColumn.compressedSize.identifier, ArchiveViewerColumn.uncompressedSize.identifier:
                if !archiveItem.isFolder {
                    let sizeAsString = (columnIdentifier == ArchiveViewerColumn.compressedSize.identifier)
                        ? SystemHelper.shared.format(bytes: archiveItem.compressedSize)
                        : SystemHelper.shared.format(bytes: archiveItem.uncompressedSize)

                    let textField = NSTextField(labelWithString: sizeAsString)
                    cellView.addSubview(textField)
                    textField.alignment = .right
                    textField.translatesAutoresizingMaskIntoConstraints = false
                    textField.textColor = .secondaryLabelColor

                    NSLayoutConstraint.activate([
                        textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -8),
                        textField.leadingAnchor.constraint(greaterThanOrEqualTo: cellView.leadingAnchor, constant: 8),
                        textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
                    ])
                }

            case ArchiveViewerColumn.modificationDate.identifier:
                if let date = archiveItem.modificationDate {
                    let dateAsString = SystemHelper.shared.formatDate(date)

                    let textField = NSTextField(labelWithString: archiveItem.isFolder ? "" : dateAsString)
                    cellView.addSubview(textField)
                    textField.translatesAutoresizingMaskIntoConstraints = false
                    textField.textColor = .secondaryLabelColor

                    NSLayoutConstraint.activate([
                        textField.trailingAnchor.constraint(lessThanOrEqualTo: cellView.trailingAnchor, constant: -8),
                        textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                        textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
                    ])
                }

            case ArchiveViewerColumn.posixPermissions.identifier:
                if let permissions = archiveItem.posixPermissions {
                    let permissionsAsString = SystemHelper.shared.formatPosixPermissions(permissions)

                    let textField = NSTextField(labelWithString: permissionsAsString)
                    cellView.addSubview(textField)
                    textField.translatesAutoresizingMaskIntoConstraints = false
                    textField.textColor = .secondaryLabelColor

                    NSLayoutConstraint.activate([
                        textField.trailingAnchor.constraint(lessThanOrEqualTo: cellView.trailingAnchor, constant: -8),
                        textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                        textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
                    ])
                }

            default:
                break
            }

            return cellView
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outlineView = notification.object as? NSOutlineView else { return }
            let items: [ArchiveItem] = outlineView.selectedRowIndexes.compactMap { row in
                outlineView.item(atRow: row) as? ArchiveItem
            }
            parent.archiveState.selectedItems = items
        }

        // MARK: - Double Click

        @objc func doubleClicked(_ sender: AnyObject) {
            guard let outlineView = sender as? NSOutlineView else { return }
            let clickedRow = outlineView.clickedRow
            guard clickedRow >= 0, let item = outlineView.item(atRow: clickedRow) as? ArchiveItem else { return }

            if item.isFolder {
                if outlineView.isItemExpanded(item) {
                    outlineView.collapseItem(item)
                } else {
                    outlineView.expandItem(item)
                }
            } else {
                parent.archiveState.open(item: item)
            }
        }

        // MARK: - Context Menu

        @objc func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let outlineView = contextOutlineView else { return }

            let clicked = outlineView.clickedRow
            if clicked >= 0 && !outlineView.selectedRowIndexes.contains(clicked) {
                outlineView.selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
            }

            let state = parent.archiveState
            let hasSelection = !state.selectedItems.isEmpty

            let open = NSMenuItem(
                title: String(localized: "Open", comment: "Context menu: open the clicked item"),
                action: #selector(contextOpen(_:)), keyEquivalent: "")
            open.target = self
            open.image = NSImage(systemSymbolName: "arrow.up.forward.square", accessibilityDescription: nil)
            open.isEnabled = hasSelection
            menu.addItem(open)

            let quickLook = NSMenuItem(
                title: String(localized: "Quick Look", comment: "Context menu: preview the clicked item"),
                action: #selector(contextQuickLook(_:)), keyEquivalent: " ")
            quickLook.keyEquivalentModifierMask = []
            quickLook.target = self
            quickLook.image = NSImage(named: "custom.document.badge.eye")
            quickLook.isEnabled = hasSelection
            menu.addItem(quickLook)

            menu.addItem(.separator())

            let extract = NSMenuItem(
                title: String(localized: "Extract Selected…", comment: "Context menu: extract the selected items to a folder"),
                action: #selector(contextExtract(_:)), keyEquivalent: "")
            extract.target = self
            extract.image = NSImage(named: "custom.document.badge.arrow.down")
            extract.isEnabled = hasSelection
            menu.addItem(extract)

            menu.addItem(.separator())

            let delete = NSMenuItem(
                title: String(localized: "Delete", comment: "Context menu: delete the selected items from the archive"),
                action: #selector(contextDelete(_:)), keyEquivalent: "\u{8}")
            delete.keyEquivalentModifierMask = []
            delete.target = self
            delete.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
            delete.isEnabled = hasSelection && state.canBeEdited && !state.isSaving
            menu.addItem(delete)
        }

        @objc func contextOpen(_ sender: Any?) {
            guard let item = parent.archiveState.selectedItems.first else { return }
            if item.isFolder, let outlineView = contextOutlineView {
                if outlineView.isItemExpanded(item) {
                    outlineView.collapseItem(item)
                } else {
                    outlineView.expandItem(item)
                }
            } else {
                parent.archiveState.open(item: item)
            }
        }

        @objc func contextQuickLook(_ sender: Any?) {
            parent.archiveState.updateSelectedItemForQuickLook()
        }

        @objc func contextExtract(_ sender: Any?) {
            let state = parent.archiveState
            let items = state.selectedItems
            guard !items.isEmpty else { return }
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = String(localized: "Extract", comment: "Prompt of the folder picker used to extract items")
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                Task { @MainActor in
                    state.extract(items: items, to: url)
                }
            }
        }

        @objc func contextDelete(_ sender: Any?) {
            let state = parent.archiveState
            guard state.canBeEdited, !state.selectedItems.isEmpty else { return }
            state.remove(items: state.selectedItems)
        }

        // MARK: - File Promise Provider

        @MainActor func filePromiseProvider(
            _ filePromiseProvider: NSFilePromiseProvider,
            fileNameForType fileType: String
        ) -> String {
            (filePromiseProvider.userInfo as? ArchiveItem)?.name ?? "unknown"
        }

        @MainActor func filePromiseProvider(
            _ filePromiseProvider: NSFilePromiseProvider,
            writePromiseTo url: URL,
            completionHandler: @escaping (Error?) -> Void
        ) {
            guard let item = filePromiseProvider.userInfo as? ArchiveItem else {
                log.error("Could not fulfill file promise")
                return completionHandler(NSError(domain: "Drag", code: 1))
            }
            Task {
                do {
                    try await parent.archiveState.fulfillDrag(item: item, to: url)
                    completionHandler(nil)
                } catch {
                    log.error("File promise extraction failed: \(error)")
                    completionHandler(error)
                }
            }
        }

        func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
            filePromiseQueue
        }
    }

    func openPreview() {
        if archiveState.previewItemUrl != nil {
            archiveState.previewItemUrl = nil
        } else {
            archiveState.updateSelectedItemForQuickLook()
        }
    }

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()

        let outlineView = ArchiveOutlineView()
        outlineView.openPreview = openPreview
        outlineView.state = archiveState
        outlineView.sortDescriptors = [NSSortDescriptor(key: defaultOrderColumn.rawValue, ascending: defaultOrderColumnAscending)]
        outlineView.startObserver()

        scrollView.documentView = outlineView

        createColumns(outlineView)
        outlineView.delegate = context.coordinator
        outlineView.dataSource = context.coordinator
        outlineView.target = context.coordinator
        outlineView.style = .fullWidth
        outlineView.allowsMultipleSelection = true
        outlineView.usesAlternatingRowBackgroundColors = true
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)
        outlineView.columnAutoresizingStyle = .noColumnAutoresizing

        outlineView.doubleAction = #selector(Coordinator.doubleClicked(_:))

        let menu = NSMenu()
        menu.delegate = context.coordinator
        menu.autoenablesItems = false
        context.coordinator.contextOutlineView = outlineView
        context.coordinator.outlineView = outlineView
        outlineView.menu = menu

        outlineView.deleteSelected = { [coordinator = context.coordinator] in
            coordinator.contextDelete(nil)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let outlineView = nsView.documentView as? NSOutlineView {
            if let col = outlineView.tableColumn(withIdentifier: ArchiveViewerColumn.compressedSize.identifier) {
                col.isHidden = !showCompressedSizeColumn
            }
            if let col = outlineView.tableColumn(withIdentifier: ArchiveViewerColumn.uncompressedSize.identifier) {
                col.isHidden = !showUncompressedSizeColumn
            }
            if let col = outlineView.tableColumn(withIdentifier: ArchiveViewerColumn.modificationDate.identifier) {
                col.isHidden = !showModificationDateColumn
            }
            if let col = outlineView.tableColumn(withIdentifier: ArchiveViewerColumn.posixPermissions.identifier) {
                col.isHidden = !showPosixPermissionsColumn
            }
        }

        if isReloadNeeded {
            guard let outlineView = nsView.documentView as? NSOutlineView else { return }
            DispatchQueue.main.async {
                context.coordinator.invalidateChildrenCache()
                outlineView.reloadData()

                let currentSelectedIDs = Set(archiveState.selectedItems.map(\.id))
                var rowIndexes = IndexSet()
                for row in 0..<outlineView.numberOfRows {
                    if let item = outlineView.item(atRow: row) as? ArchiveItem,
                       currentSelectedIDs.contains(item.id) {
                        rowIndexes.insert(row)
                    }
                }
                if !rowIndexes.isEmpty {
                    outlineView.selectRowIndexes(rowIndexes, byExtendingSelection: false)
                }

                isReloadNeeded = false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Columns Setup

    func createColumns(_ outlineView: NSOutlineView) {
        let colName = NSTableColumn(identifier: ArchiveViewerColumn.name.identifier)
        colName.title = NSLocalizedString("Name", comment: "Column that shows the name of the archive files")
        colName.width = 300
        colName.resizingMask = .userResizingMask
        colName.sortDescriptorPrototype = NSSortDescriptor(key: ArchiveSortOrder.name.rawValue, ascending: true)
        outlineView.addTableColumn(colName)
        outlineView.outlineTableColumn = colName

        let colSizeCompressed = NSTableColumn(identifier: ArchiveViewerColumn.compressedSize.identifier)
        colSizeCompressed.title = NSLocalizedString("Packed Size", comment: "Column that shows the packed size of the archive files")
        colSizeCompressed.width = 100
        colSizeCompressed.sortDescriptorPrototype = NSSortDescriptor(key: ArchiveSortOrder.compressedSize.rawValue, ascending: true)
        outlineView.addTableColumn(colSizeCompressed)

        let colSizeUncompressed = NSTableColumn(identifier: ArchiveViewerColumn.uncompressedSize.identifier)
        colSizeUncompressed.title = NSLocalizedString("Size", comment: "Column that shows the unpacked size of the archive files")
        colSizeUncompressed.width = 100
        colSizeUncompressed.sortDescriptorPrototype = NSSortDescriptor(key: ArchiveSortOrder.uncompressedSize.rawValue, ascending: true)
        outlineView.addTableColumn(colSizeUncompressed)

        let colModDate = NSTableColumn(identifier: ArchiveViewerColumn.modificationDate.identifier)
        colModDate.title = NSLocalizedString("Date Modified", comment: "Column that shows the date the file was modified")
        colModDate.width = 150
        colModDate.sortDescriptorPrototype = NSSortDescriptor(key: ArchiveSortOrder.modificationDate.rawValue, ascending: true)
        outlineView.addTableColumn(colModDate)

        let colPosInArchive = NSTableColumn(identifier: ArchiveViewerColumn.posixPermissions.identifier)
        colPosInArchive.title = NSLocalizedString("Permissions", comment: "Column that shows the file permissions")
        colPosInArchive.width = 80
        colPosInArchive.sortDescriptorPrototype = NSSortDescriptor(key: ArchiveSortOrder.posixPermissions.rawValue, ascending: true)
        outlineView.addTableColumn(colPosInArchive)
    }
}

// MARK: - ArchiveOutlineView

class ArchiveOutlineView: NSOutlineView, NSMenuItemValidation {
    var openPreview: (() -> Void)?
    var deleteSelected: (() -> Void)?
    var state: ArchiveState?

    private var observerKeys: Any?

    deinit {
        MainActor.assumeIsolated {
            if let observerKeys { NSEvent.removeMonitor(observerKeys) }
        }
    }

    func startObserver() {
        observerKeys = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            if let state = self.state, state.previewItemUrl != nil {
                if event.keyCode == 125 || event.keyCode == 126 {
                    self.forwardSuperKeyDown(with: event)
                    return nil
                }
            }
            return event
        }
    }

    private func forwardSuperKeyDown(with event: NSEvent) {
        super.keyDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 {
            openPreview?()
        } else if event.keyCode == 51 || event.keyCode == 117 {
            deleteSelected?()
        } else {
            super.keyDown(with: event)
        }
    }

    @objc func delete(_ sender: Any?) {
        deleteSelected?()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(delete(_:)) {
            guard let state else { return false }
            return state.canBeEdited && !state.selectedItems.isEmpty && !state.isSaving
        }
        return true
    }
}

