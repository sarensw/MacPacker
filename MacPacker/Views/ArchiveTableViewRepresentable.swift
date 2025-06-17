//
//  ArchiveTableView.swift
//  MacPacker
//
//  Created by Arenswald, Stephan (059) on 30.08.23.
//

import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Cocoa

class FilePromiseProvider: NSFilePromiseProvider {
    
    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var types = super.writableTypes(for: pasteboard)
        types.append(.fileURL)
        return types
    }
    
    public override func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard)
        -> NSPasteboard.WritingOptions {
            return super.writingOptions(forType: type, pasteboard: pasteboard)
    }

}

/// Coordinator for the table
/// NSPasteboardItemDataProvider


/// Table representable
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
        var itemDragged: ArchiveItem?
        
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
            let textField = NSTextField(labelWithString: item.name)
            cellView.addSubview(textField)
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor).isActive = true
            
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
        
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard let item = parent.archiveState.archive?.items[row] else { return nil }
            
            // get the item being dragged
            itemDragged = item

            // use that item to define the uttype and create the promise provider
            let typeIdentifier = UTType(filenameExtension: item.ext)
            let provider = FilePromiseProvider(fileType: typeIdentifier!.identifier, delegate: self)
            
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
                    parent.archiveState.selectedItem = nil
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
                parent.selection = tableView.selectedRowIndexes
            }
        }
        
        //
        // MARK: File Promise
        // The following methods are used to drag a file out of the archive to another app
        //
        
        func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
            if let name = itemDragged?.name {
                return name
            }
            return "unknown"
        }
        
        func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,
                                 writePromiseTo url: URL,
                                 completionHandler: @escaping (Error?) -> Void) {
            
            if let archive = parent.archiveState.archive,
               let itemDragged {
                do {
                    guard let tempUrl = archive.extractFileToTemp(itemDragged) else { return }
                    try FileManager.default.copyItem(at: tempUrl, to: url)
                    completionHandler(nil)
                    url.stopAccessingSecurityScopedResource()
                } catch {
                    print("ran into error")
                    print(error)
                    completionHandler(error)
                    url.stopAccessingSecurityScopedResource()
                }
            } else {
                print("file promise requirements are not met")
                completionHandler(nil)
                url.stopAccessingSecurityScopedResource()
            }
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
        print("isReloadNeeded: \(isReloadNeeded) \(Date.now.description)")
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
