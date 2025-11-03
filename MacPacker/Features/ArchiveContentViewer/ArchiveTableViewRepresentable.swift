//
//  ArchiveTableView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 30.08.23.
//

import AppKit
import Cocoa
import Foundation
import MacPackerCore
import SwiftUI
import UniformTypeIdentifiers

enum ArchiveViewerColumn: String, CaseIterable {
    case name
    case compressedSize
    case uncompressedSize
    case modificationDate
    case posixPermissions

    var identifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(self.rawValue)
    }

    init?(identifier: NSUserInterfaceItemIdentifier) {
        self.init(rawValue: identifier.rawValue)
    }
}

struct ArchiveTableViewRepresentable: NSViewRepresentable {
    @Binding var selection: IndexSet?
    @Binding var isReloadNeeded: Bool
    @EnvironmentObject var archiveState: ArchiveState
    
    @Binding var showCompressedSizeColumn: Bool
    @Binding var showUncompressedSizeColumn: Bool
    @Binding var showModificationDateColumn: Bool
    @Binding var showPosixPermissionsColumn: Bool
    
    //
    // MARK: Coordinator
    //
    
    /// Coordinator used to sync with the SwiftUI code portion
    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSFilePromiseProviderDelegate {
        var parent: ArchiveTableViewRepresentable
        
        var filePromiseQueue: OperationQueue = {
            let queue = OperationQueue()
            return queue
        }()
        
        init(_ parent: ArchiveTableViewRepresentable) {
            self.parent = parent
        }
        
        func numberOfRows(in tableView: NSTableView) -> Int {
            guard let archive = parent.archiveState.archive else { return 0 }
            return archive.items.count
        }
        
        /// As soon as any of the columns returns true in this func, then a right click
        /// on the column header by the user shows a menu to change the visibility
        /// of single or all columns
        /// - Parameters:
        ///   - tableView: the table view
        ///   - column: the column to return whether changing the visibility is allowed or now
        /// - Returns: true in case the column can be hidden, false otherwise
        func tableView(
            _ tableView: NSTableView,
            userCanChangeVisibilityOf column: NSTableColumn
        ) -> Bool {
            // make sure the name column is always shown
            if column.identifier == ArchiveViewerColumn.name.identifier {
                return false
            }
            return true
        }
        
        /// Receives the user choice of hiding / showing a column and makes sure the SwiftUI
        /// view can store this in AppStorage
        /// - Parameters:
        ///   - tableView: table view
        ///   - columns: list of columns that have a changed visibility
        func tableView(
            _ tableView: NSTableView,
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
            
        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard let columnIdentifier = tableColumn?.identifier else { return nil }
            guard let item = parent.archiveState.archive?.items[row] else { return nil }
            
            let cellView = NSTableCellView()
            cellView.identifier = columnIdentifier
            cellView.backgroundStyle = .raised
            
            if columnIdentifier == ArchiveViewerColumn.name.identifier {
                var imageView: NSImageView?
                if item.type == .directory {
                    let folderIcon = SystemHelper.shared.getNSImageForFolder()
                    folderIcon.size = NSSize(width: 16, height: 16)
                    imageView = NSImageView(image: folderIcon)
                } else if item.type == .file || item.type == .archive {
                    // get the icon for the file type
                    if let fileIcon = SystemHelper.shared.getNSImageByExtension(fileName: item.name) {
                        fileIcon.size = NSSize(width: 16, height: 16)
                        imageView = NSImageView(image: fileIcon)
                    }
                }
                
                let textField = NSTextField(labelWithString: item.name)
                cellView.addSubview(textField)
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.usesSingleLineMode = true
                textField.lineBreakMode = .byTruncatingTail
//                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor).isActive = true
                
                if let imageView {
                    cellView.addSubview(imageView)
                    imageView.translatesAutoresizingMaskIntoConstraints = false
//                    .isActive = true
                    
//                    textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 5).isActive = true
                    
                    NSLayoutConstraint.activate([
                        imageView.widthAnchor.constraint(equalToConstant: 16),
                        imageView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor),
                        textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 5),
                        textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor),
                        textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                        imageView.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
                    ])
                    
                    
                } else {
                    NSLayoutConstraint.activate([
                        textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor),
                        textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor),
                        textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
                    ])
                }
            } else if columnIdentifier == ArchiveViewerColumn.compressedSize.identifier || columnIdentifier == ArchiveViewerColumn.uncompressedSize.identifier {
                let sizeAsString = (columnIdentifier == ArchiveViewerColumn.compressedSize.identifier)
                    ? SystemHelper.shared.format(bytes: item.compressedSize)
                    : SystemHelper.shared.format(bytes: item.uncompressedSize)
                
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
            } else if columnIdentifier == ArchiveViewerColumn.modificationDate.identifier {
                if let date = item.modificationDate {
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
            } else if columnIdentifier == ArchiveViewerColumn.posixPermissions.identifier {
                if let permissions = item.posixPermissions {
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
            }
            
            return cellView
        }
        
        // ---
        // Drag function to external application using a promise
        //
        // This is required for Finder and similar application where a file promise is expected.
        // But this won't work for applications that need a URL.
        //
        // In this case, I would need a URL promise instead of a file promise
        // ---
        
        func tableView(
            _ tableView: NSTableView,
            pasteboardWriterForRow row: Int
        ) -> NSPasteboardWriting? {
            Logger.debug("Starting to drag item in row \(row)")
            
            guard let item = parent.archiveState.archive?.items[row] else { return nil }
            
            // ignore the parent item
            if item.type == .parent || item.type == .unknown { return nil }
            
            // use that item to define the uttype and create the promise provider
            let typeId = (item.ext.isEmpty
                 ? UTType.data                  // or UTType.item
                 : UTType(filenameExtension: item.ext))?.identifier
                 ?? UTType.data.identifier
                
            let provider = NSFilePromiseProvider(
                fileType: typeId,
                delegate: self
            )
            provider.userInfo = item
                
            return provider
            
        }
        
        /// Handles the double-click functionality. The default use case is that the item is opened using the system editor.
        /// If a directory is double clicked, then go into this directory.
        /// - Parameter sender: <#sender description#>
        @objc func doubleClicked(_ sender: AnyObject) {
            guard let tableView = sender as? NSTableView else { return }
            
            let clickedRow = tableView.clickedRow
            if clickedRow >= 0 {
                guard let archive = parent.archiveState.archive else { return }
                let item = archive.items[clickedRow]
                // Handle double-click action here
                print("Double-clicked row: \(clickedRow)")
                do {
                    _ = try archive.open(item)
                    parent.isReloadNeeded = true
                    parent.archiveState.selectedItems = []
                    tableView.deselectAll(nil)
                } catch {
                    print(error)
                }
            }
        }
        
        /// Handles the selection event in the table. When an item is selected, set the item in the store so
        /// that any other part of the code is able to understand that the selection has changed.
        /// - Parameter notification: notification
        func tableViewSelectionDidChange(_ notification: Notification) {
            if let tableView = notification.object as? NSTableView {
                print(tableView.selectedRowIndexes.count.description)
                tableView.selectedRowIndexes.forEach { print($0) }
                parent.selection = tableView.selectedRowIndexes
            }
        }
        
        //
        // MARK: File Promise
        // The following methods are used to drag a file out of the archive to another app
        //
        
        func filePromiseProvider(
            _ filePromiseProvider: NSFilePromiseProvider,
            fileNameForType fileType: String
        ) -> String {
            (filePromiseProvider.userInfo as? ArchiveItem)?.name ?? "unknown"
        }
        
        func filePromiseProvider(
            _ filePromiseProvider: NSFilePromiseProvider,
            writePromiseTo url: URL,
            completionHandler: @escaping (Error?) -> Void
        ) {
            guard
                let archive = parent.archiveState.archive,
                let item = filePromiseProvider.userInfo as? ArchiveItem
            else {
                Logger.error("Could not fulfill file promise")
                return completionHandler(NSError(domain: "Drag", code: 1))
            }
            
            let service = ArchiveService()
            service.extract(
                archive: archive,
                items: [item],
                to: url.deletingLastPathComponent() // delete because writePromiseTo will give you all
            )
            
            completionHandler(nil)
        }
        
        func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
            return filePromiseQueue
        }
    }
    
    func openSelected(_ tableView: NSTableView) {
        guard let archive = archiveState.archive else { return }
        guard let item = archiveState.selectedItems.first else { return }
        _ = try? archive.open(item)
        isReloadNeeded = true
        archiveState.selectedItems = []
        tableView.deselectAll(nil)
    }
    
    func openParent(_ tableView: NSTableView) {
        guard let archive = archiveState.archive else { return }
        guard archive.items.first == .parent else { return }
        _ = try? archive.open(archive.items.first!)
        isReloadNeeded = true
        archiveState.selectedItems = []
        tableView.deselectAll(nil)
    }
    
    func openPreview() {
        archiveState.updateSelectedItemForQuickLook()
    }
    
    //
    // Constructor
    //
    
    //
    // NSViewRepresentable
    //
    
    /// makeNSView
    /// - Parameter context: context
    /// - Returns: desc
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        
        let tableView = ArchiveTableView()
        tableView.openSelected = openSelected
        tableView.openParent = openParent
        tableView.openPreview = openPreview
        
        // make sure the table is scrollable
        scrollView.documentView = tableView
        
        // set up the table
        createColumns(tableView)
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.target = context.coordinator
        tableView.style = .fullWidth
        tableView.allowsMultipleSelection = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        
        tableView.doubleAction = #selector(Coordinator.doubleClicked(_:))
        
        return scrollView
    }
    
    /// updateNSView
    /// - Parameters:
    ///   - nsView: desc
    ///   - context: context
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if isReloadNeeded {
            Logger.log(
                level: isReloadNeeded ? .Warning : .Debug,
                "isReloadNeeded: \(isReloadNeeded)"
            )
        }
        
        if let tableView = nsView.documentView as? NSTableView {
            if let col = tableView.tableColumn(withIdentifier: ArchiveViewerColumn.compressedSize.identifier) {
                col.isHidden = !showCompressedSizeColumn
            }
            if let col = tableView.tableColumn(withIdentifier: ArchiveViewerColumn.uncompressedSize.identifier) {
                col.isHidden = !showUncompressedSizeColumn
            }
            if let col = tableView.tableColumn(withIdentifier: ArchiveViewerColumn.modificationDate.identifier) {
                col.isHidden = !showModificationDateColumn
            }
            if let col = tableView.tableColumn(withIdentifier: ArchiveViewerColumn.posixPermissions.identifier) {
                col.isHidden = !showPosixPermissionsColumn
            }
        }
        
        if isReloadNeeded {
            let tableView = (nsView.documentView as! NSTableView)
            DispatchQueue.main.async {
                tableView.reloadData()
                isReloadNeeded = false
            }
        }
    }
    
    /// create the coordinator
    /// - Returns: coordinator
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    //
    // Table related setup
    //
    
    func createColumns(_ tableView: NSTableView) {
        let colName = NSTableColumn(identifier: ArchiveViewerColumn.name.identifier)
        colName.title = NSLocalizedString("Name", comment: "Column that shows the name of the archive files")
        colName.width = 300
        colName.resizingMask = .userResizingMask
        tableView.addTableColumn(colName)
        
        let colSizeCompressed = NSTableColumn(identifier: ArchiveViewerColumn.compressedSize.identifier)
        colSizeCompressed.title = NSLocalizedString("Packed Size", comment: "Column that shows the packed size of the archive files")
        colSizeCompressed.width = 100
        tableView.addTableColumn(colSizeCompressed)
        
        let colSizeUncompressed = NSTableColumn(identifier: ArchiveViewerColumn.uncompressedSize.identifier)
        colSizeUncompressed.title = NSLocalizedString("Size", comment: "Column that shows the unpacked size of the archive files")
        colSizeUncompressed.width = 100
        tableView.addTableColumn(colSizeUncompressed)
        
        let colModDate = NSTableColumn(identifier: ArchiveViewerColumn.modificationDate.identifier)
        colModDate.title = NSLocalizedString("Date Modified", comment: "Column that shows the date the file was modified")
        colModDate.width = 150
        tableView.addTableColumn(colModDate)
        
        let colPosInArchive = NSTableColumn(identifier: ArchiveViewerColumn.posixPermissions.identifier)
        colPosInArchive.title = NSLocalizedString("Permissions", comment: "Column that shows the file permissions")
        colPosInArchive.width = 80
        tableView.addTableColumn(colPosInArchive)
    }
    
    //
    // Functions
    //
}

class ArchiveTableView: NSTableView {
    var openSelected: ((NSTableView) -> Void)?
    var openParent: ((NSTableView) -> Void)?
    var openPreview: (() -> Void)?
    
    override func keyDown(with event: NSEvent) {
        
        if event.keyCode == 49 {
            openPreview?()
        } else if event.keyCode == 125 && event.modifierFlags.contains(.command) {
            openSelected?(self)
        } else if event.keyCode == 126 && event.modifierFlags.contains(.command) {
            openParent?(self)
        } else {
            super.keyDown(with: event)
        }
    }
}
