//
//  ArchiveOutlineViewController.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 05.10.25.
//

import AppKit
import Core
import UniformTypeIdentifiers

class ArchiveViewController: NSViewController {
    var state: ArchiveState? {
        didSet {
            outlineView.reloadData()
        }
    }

    /// Nested archives currently being extracted, so their row shows a spinner
    /// while it happens — reading one means unpacking it first, which is not
    /// instant for a large archive.
    private var loadingItems: Set<UUID> = []

    var selectedItems: [ArchiveItem]? {
        guard outlineView.selectedRowIndexes.count > 0 else {
            return nil
        }
        return outlineView.selectedRowIndexes.compactMap { row in
            outlineView.item(atRow: row) as? ArchiveItem
        }
    }
    
    private let scrollView = NSScrollView()
    private let outlineView = NSOutlineView()
    
    var filePromiseQueue: OperationQueue = {
        let queue = OperationQueue()
        return queue
    }()
    
    override func loadView() {
        let clipView = NSClipView()
        clipView.documentView = outlineView
        scrollView.contentView = clipView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        outlineView.headerView = NSTableHeaderView()
        outlineView.allowsColumnReordering = false
        outlineView.allowsColumnResizing = true
        outlineView.allowsMultipleSelection = true
        outlineView.rowHeight = 22
        outlineView.autosaveTableColumns = false
        outlineView.delegate = self
        outlineView.dataSource = self
        outlineView.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: false)
        outlineView.usesAlternatingRowBackgroundColors = true
        outlineView.selectionHighlightStyle = .regular
        outlineView.style = .fullWidth
        outlineView.rowSizeStyle = .small
        outlineView.gridStyleMask = []
        
        createColumns(outlineView)
        
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
    
    
    /// The window's columns, in the window's order, shown or hidden as the
    /// window shows them and sorted by the window's choice: the settings live
    /// in the app group the preview reads (#251 B9, B10, H6).
    func createColumns(_ outlineView: NSOutlineView) {
        let columns: [(ArchiveViewerColumn, String, CGFloat, ArchiveSortOrder, String?)] = [
            (.name, String(localized: "Name", bundle: .module, comment: "Column that shows the name of the archive files"),
             300, .name, nil),
            (.compressedSize, String(localized: "Packed Size", bundle: .module, comment: "Column that shows the packed size of the archive files"),
             100, .compressedSize, Keys.showColumnCompressedSize),
            (.uncompressedSize, String(localized: "Size", bundle: .module, comment: "Column that shows the unpacked size of the archive files"),
             100, .uncompressedSize, Keys.showColumnUncompressedSize),
            (.modificationDate, String(localized: "Date Modified", bundle: .module, comment: "Column that shows the date the file was modified"),
             150, .modificationDate, Keys.showColumnModificationDate),
            (.posixPermissions, String(localized: "Permissions", bundle: .module, comment: "Column that shows the Unix permissions of the archive files, such as -rw-r--r--"),
             80, .posixPermissions, Keys.showColumnPosixPermissions),
        ]
        for (column, title, width, order, setting) in columns {
            let tableColumn = NSTableColumn(identifier: column.identifier)
            tableColumn.title = title
            tableColumn.width = width
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: order.rawValue, ascending: true)
            if column == .name { tableColumn.resizingMask = .userResizingMask }
            if let setting { tableColumn.isHidden = !Keys.showsColumn(setting) }
            outlineView.addTableColumn(tableColumn)
        }

        let sortOrder = Keys.sortOrder()
        outlineView.sortDescriptors = [NSSortDescriptor(key: sortOrder.column.rawValue, ascending: sortOrder.ascending)]
    }
}

extension ArchiveViewController: NSOutlineViewDataSource, NSOutlineViewDelegate {
//    private var rootNode: ArchiveItem { hierarchy?.root ?? .root }
    
    /// Resolves the child UUIDs stored on an `ArchiveItem` (or on the root, when
    /// `item` is `nil`) into the actual `ArchiveItem`s the list shows, via
    /// `state.listedChildren(of:)` — the same as the archive window, hidden
    /// files included only when they are shown.
    ///
    /// `ArchiveItem.children` holds `[UUID]` (changed in `4659e4a`), so the
    /// outline view has to look the items up here. Returning the raw UUIDs makes
    /// every `as? ArchiveItem` cast in `viewFor` / `isItemExpandable` fail, which
    /// is why the preview showed empty, non-expandable rows.
    private func resolvedChildren(of item: Any?) -> [ArchiveItem] {
        guard let state, let node = (item as? ArchiveItem) ?? state.root else { return [] }
        return state.displayedChildren(of: node)
    }

    /// A click on a header sorts by that column, here and in the window: the
    /// choice goes to the app group both read.
    func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = outlineView.sortDescriptors.first,
              let key = descriptor.key, let column = ArchiveSortOrder(rawValue: key) else { return }
        // Setting up the header lands here too: only a change is saved, or a
        // preview shown before the app's first launch would store the default
        // over the order the app carries over.
        let current = Keys.sortOrder()
        if current.column != column || current.ascending != descriptor.ascending {
            UserDefaults.macPackerShared.set(key, forKey: Keys.defaultOrderColumn)
            UserDefaults.macPackerShared.set(descriptor.ascending, forKey: Keys.defaultOrderColumnAscending)
        }
        outlineView.reloadData()
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        resolvedChildren(of: item).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        resolvedChildren(of: item)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if !resolvedChildren(of: item).isEmpty { return true }
        return isUnopenedArchive(item)
    }

    /// A nested archive gets a disclosure triangle before anything is known
    /// about its contents; the first click is what unpacks it.
    private func isUnopenedArchive(_ item: Any) -> Bool {
        guard let state,
              let archiveItem = item as? ArchiveItem,
              archiveItem.type == .file,
              archiveItem.children == nil else { return false }
        // Extension only — the entry is still inside the archive, so there are
        // no bytes to sniff until it has been extracted.
        return state.looksLikeArchive(url: URL(fileURLWithPath: archiveItem.name))
    }

    func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
        guard let archiveItem = item as? ArchiveItem, isUnopenedArchive(item) else { return true }
        // Nothing to expand yet: unpack first and expand when the entries are in.
        openNestedArchive(archiveItem)
        return false
    }

    /// Extracts a nested archive to a temporary location and hangs its contents
    /// under the row, so the tree keeps going into it.
    private func openNestedArchive(_ item: ArchiveItem) {
        guard let state, loadingItems.insert(item.id).inserted else { return }
        outlineView.reloadItem(item)
        PreviewLog.general.info("Opening nested archive", context: ["name": item.name])

        Task {
            do {
                try await state.openAsync(item: item)
                PreviewLog.general.info("Nested archive opened", context: [
                    "name": item.name,
                    "items": "\(item.children?.count ?? 0)"
                ])
            } catch {
                // The row stays collapsed and openable, so this is retryable.
                PreviewLog.general.error("Nested archive failed to open", context: [
                    "name": item.name,
                    "error": error.localizedDescription
                ])
            }
            loadingItems.remove(item.id)
            outlineView.reloadItem(item, reloadChildren: true)
            if !resolvedChildren(of: item).isEmpty {
                outlineView.expandItem(item)
            }
        }
    }


    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        guard let columnIdentifier = tableColumn?.identifier else { return nil }
        guard let archiveItem = item as? ArchiveItem else { return nil }
        
        let cellView = NSTableCellView()
        cellView.identifier = columnIdentifier
        // greyed out, as Finder shows a hidden file
        if archiveItem.isHidden { cellView.alphaValue = 0.5 }

        switch columnIdentifier {
        case ArchiveViewerColumn.name.identifier:
            // Image — or a spinner while this nested archive is being unpacked
            let leadingView: NSView
            if loadingItems.contains(archiveItem.id) {
                let spinner = NSProgressIndicator()
                spinner.style = .spinning
                spinner.controlSize = .small
                spinner.isIndeterminate = true
                spinner.startAnimation(nil)
                leadingView = spinner
            } else {
                let iconView = NSImageView()
                iconView.imageScaling = .scaleProportionallyDown

                let icon: NSImage? = {
                    if archiveItem.isFolder {
                        return SystemHelper.shared.getNSImageForFolder()
                    } else {
                        return SystemHelper.shared.getNSImageByExtension(fileName: archiveItem.name)
                    }
                }()
                iconView.image = icon
                iconView.image?.size = NSSize(width: 16, height: 16)

                // Wire up standard properties (handy for accessibility/reuse expectations)
                cellView.imageView = iconView
                leadingView = iconView
            }
            leadingView.translatesAutoresizingMaskIntoConstraints = false
            leadingView.setContentHuggingPriority(.required, for: .horizontal)
            leadingView.setContentCompressionResistancePriority(.required, for: .horizontal)

            // Text
            let label = NSTextField(labelWithString: archiveItem.name)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.usesSingleLineMode = true
            label.lineBreakMode = .byTruncatingTail

            cellView.textField = label

            cellView.addSubview(leadingView)
            cellView.addSubview(label)

            NSLayoutConstraint.activate([
                leadingView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 2),
                leadingView.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                leadingView.widthAnchor.constraint(equalToConstant: 16),
                leadingView.heightAnchor.constraint(equalToConstant: 16),

                label.leadingAnchor.constraint(equalTo: leadingView.trailingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cellView.trailingAnchor),
                label.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
            ])
        case ArchiveViewerColumn.compressedSize.identifier, ArchiveViewerColumn.uncompressedSize.identifier:
            let packed = columnIdentifier == ArchiveViewerColumn.compressedSize.identifier
            addSecondaryText(EntryText.size(of: archiveItem, packed: packed), to: cellView, alignedRight: true)
        case ArchiveViewerColumn.modificationDate.identifier:
            if let date = archiveItem.modificationDate {
                addSecondaryText(EntryText.date(date), to: cellView, alignedRight: false)
            }
        case ArchiveViewerColumn.posixPermissions.identifier:
            if let permissions = archiveItem.posixPermissions {
                addSecondaryText(EntryText.permissions(permissions), to: cellView, alignedRight: false)
            }
        default:
            return cellView
        }

        return cellView
    }

    /// A size, a date or permissions: grey, as the window shows them.
    private func addSecondaryText(_ text: String, to cellView: NSTableCellView, alignedRight: Bool) {
        let textField = NSTextField(labelWithString: text)
        cellView.addSubview(textField)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.textColor = .secondaryLabelColor
        if alignedRight {
            textField.alignment = .right
            NSLayoutConstraint.activate([
                textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -8),
                textField.leadingAnchor.constraint(greaterThanOrEqualTo: cellView.leadingAnchor, constant: 8),
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                textField.trailingAnchor.constraint(lessThanOrEqualTo: cellView.trailingAnchor, constant: -8),
                textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            ])
        }
    }
}
