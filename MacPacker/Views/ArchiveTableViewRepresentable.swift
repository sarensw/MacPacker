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
    
    /** Required:
        Return an array of UTI strings of data types the receiver can write to the pasteboard.
        By default, data for the first returned type is put onto the pasteboard immediately, with the remaining types being promised.
        To change the default behavior, implement -writingOptionsForType:pasteboard: and return NSPasteboardWritingPromised
        to lazily provided data for types, return no option to provide the data for that type immediately.
     
        Use the pasteboard argument to provide different types based on the pasteboard name, if desired.
        Do not perform other pasteboard operations in the function implementation.
    */
    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var types = super.writableTypes(for: pasteboard)
        types.append(.fileURL)
        return types
    }
    
    /** Optional:
        Returns options for writing data of a type to a pasteboard.
        Use the pasteboard argument to provide different options based on the pasteboard name, if desired.
        Do not perform other pasteboard operations in the function implementation.
     */
    public override func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard)
        -> NSPasteboard.WritingOptions {
            return super.writingOptions(forType: type, pasteboard: pasteboard)
    }

}

extension Coordinator: NSFilePromiseProviderDelegate {
    
    /** This function is called at drop time to provide the title of the file being dropped.
        This sample uses a hard-coded string for simplicity, but depending on your use case, you should take the fileType parameter into account.
    */
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        // Return the photoItem's URL file name.
        if let name = itemDragged?.name {
            return name
        }
        return "unknown"
    }
    
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,
                             writePromiseTo url: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        print("filePromiseProvider")
        if let se = getCurrentStackEntry() {
            do {
                guard let archiveType = se.archiveType else { return }
                guard let itemDragged,
                      let path = try ArchiveType.with(archiveType).extractFileToTemp(
                    path: se.localPath,
                    item: itemDragged) else { return }
                print("filePromiseProvider: \(path)")
                try FileManager.default.copyItem(at: path, to: url)

                completionHandler(nil)
                url.stopAccessingSecurityScopedResource()
            } catch {
                print("ran into error")
                print(error)
                completionHandler(error)
                url.stopAccessingSecurityScopedResource()
            }
        } else {
            completionHandler(nil)
            url.stopAccessingSecurityScopedResource()
        }
    }
    
    /** You should provide a non main operation queue (e.g. one you create) via this function.
        This way you don't stall the main thread while writing the promise file.
    */
    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        return filePromiseQueue
    }
    
}

protocol TableViewEventDelegate: AnyObject {
    func tableViewKeyDown(with event: NSEvent) -> Bool
}

/// Coordinator for the table
/// NSPasteboardItemDataProvider
final class Coordinator: NSObject, TableViewEventDelegate, NSTableViewDelegate, NSTableViewDataSource {
    var archiveState: ArchiveState
    var parent: ArchiveTableViewRepresentable
    var items: [ArchiveItem] = []
    var itemDragged: ArchiveItem?
    var getCurrentStackEntry: () -> ArchiveItemStackEntry?
    
    var filePromiseQueue: OperationQueue = {
        let queue = OperationQueue()
        return queue
    }()
    
    init(_ parent: ArchiveTableViewRepresentable, archiveState: ArchiveState, getCurrentStackEntry: @escaping () -> ArchiveItemStackEntry?) {
        self.archiveState = archiveState
        self.getCurrentStackEntry = getCurrentStackEntry
        self.parent = parent
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        print("number of rows changed to \(items.count)")
//        return parent.data.count
        return items.count
    }
        
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let columnIdentifier = tableColumn?.identifier else { return nil }
        
        let cellView = NSTableCellView()
        cellView.identifier = columnIdentifier
        cellView.backgroundStyle = .raised
        let textField = NSTextField(labelWithString: items[row].name)
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
        print("")
        print("")
        print("")
        print("")
        print("")
        print("start dragging session")
        print("---")
        
        // get the item being dragged
        let item = items[row]
        itemDragged = item

        // use that item to define the uttype and create the promise provider
        let typeIdentifier = UTType(filenameExtension: item.ext)
        let provider = FilePromiseProvider(fileType: typeIdentifier!.identifier, delegate: self)
        
        return provider
    }
    
    public func moveDirectoryUp(_ item: ArchiveItem) throws {
        // let's use completePath to go up as long as possible
        print("move up directory now")

//        if let completePath,
//           var completePathUrl = URL(string: completePath) {
//            completePathUrl.deleteLastPathComponent()
//            let stackEntry = ArchiveItemStackEntry(
//                type: .Directory,
//                localPath: completePathUrl,
//                archivePath: nil,
//                tempId: nil,
//                archiveType: nil)
//            loadStackEntry(stackEntry, push: false)
//        }
    }
    
    
    /// Handles the double-click functionality. The default use case is that the item is opened using the system editor.
    /// If a directory is double clicked, then go into this directory.
    /// - Parameter sender: <#sender description#>
    @objc func doubleClicked(_ sender: AnyObject) {
        guard let tableView = sender as? NSTableView else {
            return
        }
        
        let clickedRow = tableView.clickedRow
        if clickedRow >= 0 {
            // Handle double-click action here
            print("Double-clicked row: \(clickedRow)")
            do {
                let item = items[clickedRow]
                if let archive = parent.archive {
                    let result = try archive.open(item)
//                    if result == .leaveDirectory {
//                        try moveDirectoryUp(item)
//                    }
                    parent.isReloadNeeded = true
                    archiveState.selectedItem = nil
                }
            } catch {
                print(error)
            }
        }
    }
    
    /// Handles the selection event in the table. When an item is selected, set the item in the store so
    /// that any other part of the code is able to understand that the selection has changed.
    /// - Parameter notification: notification
    func tableViewSelectionDidChange(_ notification: Notification) {
        let store = archiveState
        if let tableView = notification.object as? NSTableView {
            let indexes = tableView.selectedRowIndexes
            if let selectedIndex = indexes.first {
                let archiveItem = items[selectedIndex]
                store.selectedItem = archiveItem
            } else if indexes.isEmpty {
                store.selectedItem = nil
            }
        }
    }
    
    //
    // MARK: TableViewEventDelegate stubs
    //
    
    func tableViewKeyDown(with event: NSEvent) -> Bool {
        if event.keyCode == 49 { // SPACE
            if let archive = archiveState.archive,
               let selectedItem = archiveState.selectedItem {
                let url = archive.extractFileToTemp(selectedItem)
                InternalEditorWindowController.shared.show(url)
            }
            return true
        }
        return false
    }
}

class ArchiveTableView: NSTableView {
    weak var eventDelegate: TableViewEventDelegate?
    
    override func keyDown(with event: NSEvent) {
        if let eventDelegate {
            eventDelegate.tableViewKeyDown(with: event) ? () : super.keyDown(with: event)
        }
    }
}

/// Table representable
struct ArchiveTableViewRepresentable: NSViewRepresentable {
    @EnvironmentObject var archiveState: ArchiveState
    @Binding var isReloadNeeded: Bool
    @Binding var archive: Archive2?
    var getCurrentStackEntry: () -> ArchiveItemStackEntry?
    
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
        // make sure the table is scrollable
        scrollView.documentView = tableView
        
        // set up the table
        createColumns(tableView)
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.eventDelegate = context.coordinator
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
        // todo: make sure the data is only reloaded when needed
        if let archive {
            print("isReloadNeeded: \(isReloadNeeded) \(Date.now.description)")
            if isReloadNeeded {
                let tableView = (nsView.documentView as! NSTableView)
                //        context.coordinator.parent = self
                context.coordinator.items = archive.items
                DispatchQueue.main.async {
                    tableView.reloadData()
                    isReloadNeeded = false
                }
            }
        }
    }
    
    /// create the coordinator
    /// - Returns: coordinator
    func makeCoordinator() -> Coordinator {
        Coordinator(self, archiveState: archiveState, getCurrentStackEntry: getCurrentStackEntry)
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
