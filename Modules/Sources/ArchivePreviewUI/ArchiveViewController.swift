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
    
    
    func createColumns(_ outlineView: NSOutlineView) {
        let colName = NSTableColumn(identifier: ArchiveViewerColumn.name.identifier)
        colName.title = String(localized: "Name", comment: "Column that shows the name of the archive files")
        colName.width = 300
        colName.resizingMask = .userResizingMask
        outlineView.addTableColumn(colName)
        
        let colSizeCompressed = NSTableColumn(identifier: ArchiveViewerColumn.compressedSize.identifier)
        colSizeCompressed.title = String(localized: "Packed Size", comment: "Column that shows the packed size of the archive files")
        colSizeCompressed.width = 100
        outlineView.addTableColumn(colSizeCompressed)
        
        let colSizeUncompressed = NSTableColumn(identifier: ArchiveViewerColumn.uncompressedSize.identifier)
        colSizeUncompressed.title = String(localized: "Size", comment: "Column that shows the unpacked size of the archive files")
        colSizeUncompressed.width = 100
        outlineView.addTableColumn(colSizeUncompressed)
        
        let colModDate = NSTableColumn(identifier: ArchiveViewerColumn.modificationDate.identifier)
        colModDate.title = String(localized: "Date Modified", comment: "Column that shows the date the file was modified")
        colModDate.width = 150
        outlineView.addTableColumn(colModDate)
    }
}

extension ArchiveViewController: NSOutlineViewDataSource, NSOutlineViewDelegate {
//    private var rootNode: ArchiveItem { hierarchy?.root ?? .root }
    
    /// Resolves the child UUIDs stored on an `ArchiveItem` (or on the root, when
    /// `item` is `nil`) into the actual `ArchiveItem`s via `state.entries`.
    ///
    /// `ArchiveItem.children` holds `[UUID]` (changed in `4659e4a`), so the
    /// outline view has to look the items up here. Returning the raw UUIDs makes
    /// every `as? ArchiveItem` cast in `viewFor` / `isItemExpandable` fail, which
    /// is why the preview showed empty, non-expandable rows.
    private func resolvedChildren(of item: Any?) -> [ArchiveItem] {
        guard let state else { return [] }
        let node = (item as? ArchiveItem) ?? state.root
        guard let childIDs = node?.children else { return [] }
        return childIDs.compactMap { state.entries[$0] }
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
            if archiveItem.type != .directory {
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
                
                let textField = NSTextField(labelWithString: dateAsString)
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
            return cellView
        }
        
        return cellView
    }
}
