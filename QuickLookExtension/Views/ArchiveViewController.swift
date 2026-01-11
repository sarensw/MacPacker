//
//  ArchiveOutlineViewController.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 05.10.25.
//

import AppKit
import Core
import os
import UniformTypeIdentifiers

class ArchiveViewController: NSViewController {
    var state: ArchiveState? {
        didSet {
            outlineView.reloadData()
        }
    }
    
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
        colName.title = NSLocalizedString("Name", comment: "Column that shows the name of the archive files")
        colName.width = 300
        colName.resizingMask = .userResizingMask
        outlineView.addTableColumn(colName)
        
        let colSizeCompressed = NSTableColumn(identifier: ArchiveViewerColumn.compressedSize.identifier)
        colSizeCompressed.title = NSLocalizedString("Packed Size", comment: "Column that shows the packed size of the archive files")
        colSizeCompressed.width = 100
        outlineView.addTableColumn(colSizeCompressed)
        
        let colSizeUncompressed = NSTableColumn(identifier: ArchiveViewerColumn.uncompressedSize.identifier)
        colSizeUncompressed.title = NSLocalizedString("Size", comment: "Column that shows the unpacked size of the archive files")
        colSizeUncompressed.width = 100
        outlineView.addTableColumn(colSizeUncompressed)
        
        let colModDate = NSTableColumn(identifier: ArchiveViewerColumn.modificationDate.identifier)
        colModDate.title = NSLocalizedString("Date Modified", comment: "Column that shows the date the file was modified")
        colModDate.width = 150
        outlineView.addTableColumn(colModDate)
    }
}

extension ArchiveViewController: NSOutlineViewDataSource, NSOutlineViewDelegate {
//    private var rootNode: ArchiveItem { hierarchy?.root ?? .root }
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let state else { return 0 }
        guard let node = (item as? ArchiveItem) ?? state.root else { return 0 }
        guard let children = node.children else { return 0 }
        
        return children.count
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let state else { return 0 }
        guard let node = (item as? ArchiveItem) ?? state.root else { return 0 }
        guard let children = node.children else { return 0 }
        
        return children[index]
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? ArchiveItem else { return false }
        guard let children = node.children else { return false }
        
        return !children.isEmpty
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
            // Image
            let iconView = NSImageView()
            iconView.translatesAutoresizingMaskIntoConstraints = false
            iconView.imageScaling = .scaleProportionallyDown
            iconView.setContentHuggingPriority(.required, for: .horizontal)
            iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

            let icon: NSImage? = {
                if archiveItem.type == .directory {
                    return SystemHelper.shared.getNSImageForFolder()
                } else {
                    return SystemHelper.shared.getNSImageByExtension(fileName: archiveItem.name)
                }
            }()
            iconView.image = icon
            iconView.image?.size = NSSize(width: 16, height: 16)

            // Text
            let label = NSTextField(labelWithString: archiveItem.name)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.usesSingleLineMode = true
            label.lineBreakMode = .byTruncatingTail

            // Wire up standard properties (handy for accessibility/reuse expectations)
            cellView.imageView = iconView
            cellView.textField = label

            cellView.addSubview(iconView)
            cellView.addSubview(label)

            NSLayoutConstraint.activate([
                iconView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 2),
                iconView.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 16),
                iconView.heightAnchor.constraint(equalToConstant: 16),

                label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
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
