//
//  ArchiveTableView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 30.08.23.
//

import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Cocoa

struct ArchiveTableViewRepresentable: NSViewRepresentable {
    @Binding var selection: IndexSet?
    @Binding var isReloadNeeded: Bool
    @EnvironmentObject var archiveState: ArchiveState
    
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
            
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let columnIdentifier = tableColumn?.identifier else { return nil }
            guard let item = parent.archiveState.archive?.items[row] else { return nil }
            
            let cellView = NSTableCellView()
            cellView.identifier = columnIdentifier
            cellView.backgroundStyle = .raised
            
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
            textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor).isActive = true
            
            if let imageView {
                cellView.addSubview(imageView)
                imageView.translatesAutoresizingMaskIntoConstraints = false
                imageView.centerYAnchor.constraint(equalTo: cellView.centerYAnchor).isActive = true
                
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 5).isActive = true
                
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
        let tableView = NSTableView()
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
        
        tableView.doubleAction = #selector(Coordinator.doubleClicked(_:))
        
        return scrollView
    }
    
    /// updateNSView
    /// - Parameters:
    ///   - nsView: desc
    ///   - context: context
    func updateNSView(_ nsView: NSScrollView, context: Context) {
//        print("isReloadNeeded: \(isReloadNeeded)")
        Logger.log(
            level: isReloadNeeded ? .Warning : .Debug,
            "isReloadedNeeded: \(isReloadNeeded)"
        )
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
        let colName = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: "name"))
        colName.title = "Name"
        tableView.addTableColumn(colName)
    }
    
    //
    // Functions
    //
}
