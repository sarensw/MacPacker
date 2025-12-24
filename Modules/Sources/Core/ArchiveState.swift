//
//  ArchiveState.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 04.05.25.
//

import Combine
import Foundation
import SwiftUI

@MainActor
public class ArchiveState: ObservableObject {
    // MARK: UI
    // Basic archive metadata
    @Published private(set) public var url: URL?
    @Published private(set) public var name: String?
    @Published private(set) public var type: ArchiveTypeDto?
    @Published private(set) public var ext: String?
    
    // Full list of entries
    @Published private(set) public var entries: [ArchiveItemId: ArchiveItem] = [:]
    
    // Root item
    @Published private(set) public var root: ArchiveItem?
    
    // Currently selected item (i.e. its children are shown in the
    // table of the archive view
    @Published private(set) public var selectedItem: ArchiveItem?
    
    // Items currently selected by the user in the tree / table
    @Published public var selectedItems: [ArchiveItem] = []
    
    // UI State
    @Published private(set) public var isBusy: Bool = false
    @Published private(set) public var status: String? = nil
    @Published private(set) public var progress: Double = 0.0
    @Published private(set) public var error: String? = nil
    @Published public var isReloadNeeded: Bool = false
    
    // TODO: Still needed?
    @Published public var openWithUrls: [URL] = []
    @Published public var previewItemUrl: URL?
    
    // MARK: Logic
//    private let handlerRegistry: HandlerRegistry
//    private let formatCatalog: ArchiveTypeCatalog
    
//    private let extractor = ArchiveExtractor()
    
    private let catalog: ArchiveTypeCatalog
    private let archiveEngineSelector: ArchiveEngineSelectorProtocol
    private let archiveTypeDetector: ArchiveTypeDetector
    
//    public init(catalog: ArchiveTypeCatalog) {
//        self.catalog = catalog
//        self.archiveEngineSelector = ArchiveEngineSelector(catalog: catalog)
//        self.archiveTypeDetector = ArchiveTypeDetector(catalog: catalog)
//    }
    
    public init(catalog: ArchiveTypeCatalog, engineSelector: ArchiveEngineSelectorProtocol) {
        self.catalog = catalog
        self.archiveEngineSelector = engineSelector
        self.archiveTypeDetector = ArchiveTypeDetector(catalog: catalog)
    }
}

extension ArchiveState {
    
    //
    // MARK: General Sync
    //
    // The list of function s down here is the synchrounous pendant
    // that shall be used by the UI. This keeps the async handling and
    // task handling within the Core library
    //
    
    /// This func is called with an item that is an archive (typed as .file, but detected as supported
    /// archive) to be unfold in the sense that its hiearchy is loaded into the given hierarchy.
    /// - Parameters:
    ///   - archiveItem: item to load as archive
    ///   - engine: engine to use
    private func unfold(_ archiveItem: ArchiveItem, using engine: ArchiveEngine) {
        if let url = archiveItem.url {
            self.isBusy = true
            self.error = nil
            self.name = url.lastPathComponent
            self.ext = url.pathExtension
            
            let detector = self.archiveTypeDetector
            let selector = self.archiveEngineSelector
            
            Task {
                do {
                    let archiveLoader = ArchiveLoader(
                        archiveTypeDetector: detector,
                        archiveEngineSelector: selector
                    )
                    
                    self.status = "loading..."
                    let loaderResult = try await archiveLoader.loadEntries(url: url)
                    
                    
                    if loaderResult.error != nil {
                        self.status = "failed to load"
                        self.error = loaderResult.error
                    }
                    self.selectedItem = archiveItem
                    
                    self.status = "building tree..."
                    
                    let builderResult = await archiveLoader.buildTree(at: archiveItem)
                    
                    self.status = nil
                    self.error = builderResult.error
                    
                    self.isBusy = false
                    self.isReloadNeeded = true
                    self.selectedItems = []
                } catch {
                    self.error = error.localizedDescription
                    self.isBusy = false
                }
            }
        }
    }
    
    /// Opens the given url. Calls the async version in a Task to keep the heavy load
    /// in the library
    public func open(url: URL) {
        self.isBusy = true
        self.error = nil
        self.name = url.lastPathComponent
        self.ext = url.pathExtension
        
        let detector = self.archiveTypeDetector
        let selector = self.archiveEngineSelector
        
        Task {
            do {
                let archiveLoader = ArchiveLoader(
                    archiveTypeDetector: detector,
                    archiveEngineSelector: selector
                )
                
                self.status = "loading..."
                let loaderResult = try await archiveLoader.loadEntries(url: url)
                
                
                if loaderResult.error != nil {
                    self.status = "failed to load"
                    self.error = loaderResult.error
                }
                self.root = loaderResult.root
                self.selectedItem = loaderResult.root
                self.type = loaderResult.type
                self.entries = Dictionary(uniqueKeysWithValues: loaderResult.entries.map({ ($0.id, $0) }))
                
                self.status = "building tree..."
                
                let builderResult = await archiveLoader.buildTree(at: loaderResult.root)
                
                self.status = nil
                self.error = builderResult.error
                
                self.isBusy = false
                self.isReloadNeeded = true
                self.selectedItems = []
            } catch {
                self.error = error.localizedDescription
                self.isBusy = false
            }
        }
    }
    
    /// Opens the given item which can be anything (e.g. file, folder, archive, root, ...)
    /// - Parameter item: The item to open
    public func open(item: ArchiveItem) {
        Task.detached {
            do {
                try await self.openAsync(item: item)
                
                await MainActor.run {
                    self.isBusy = false
                    self.isReloadNeeded = true
                    self.selectedItems = []
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isBusy = false
                }
            }
        }
    }
    
    /// <#Description#>
    /// - Parameters:
    ///   - item: <#item description#>
    ///   - destination: <#destination description#>
    public func extract(
        item: ArchiveItem,
        to destination: URL
    ) {
        Task {
            do {
                if let (archiveTypeId, archiveUrl) = findHandlerAndUrl(for: item),
                   let engine = archiveEngineSelector.engine(for: archiveTypeId),
                   let temp = createTempDirectory() {
                    // first extract to our own directory where we have full rights to write to
                    let tempUrl = try await engine.extract(
                        item: item,
                        from: archiveUrl,
                        to: temp.url
                    )
                    
                    // guard the extracted url
                    guard let tempUrl else {
                        Logger.error("Could not get url for extracted file")
                        return
                    }
                    
                    // then move the file to the actual target... This is required
                    // because in case of a file promise we only get access to write
                    // to the file, but not to the directory where the file is being
                    // dragged to.
                    
                    let _ = destination.startAccessingSecurityScopedResource()
                    defer { destination.stopAccessingSecurityScopedResource() }
                    
                    Logger.debug("Extraction successful. Now moving \(tempUrl) to \(destination)")
                    
                    print(FileManager.default.fileExists(atPath: tempUrl.path))
                    print(FileManager.default.fileExists(atPath: destination.path))
                    
                    try FileManager.default.moveItem(
                        at: tempUrl,
                        to: destination)
                }
            } catch {
                Logger.error(error)
                Logger.error("Could not extract item \(item) to \(destination)")
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isBusy = false
                }
            }
        }
    }
    
    /// Extracts the given set of items to the given destination. This is usually triggered by the
    /// user from within the UI
    /// - Parameters:
    ///   - items: <#items description#>
    ///   - destination: <#destination description#>
    public func extract(
        items: [ArchiveItem],
        to destination: URL
    ) {
        
        Task {
            do {
                for item in items {
                    if let (archiveTypeId, archiveUrl) = findHandlerAndUrl(for: item),
                       let engine = archiveEngineSelector.engine(for: archiveTypeId),
                       let temp = createTempDirectory() {
                        
                        // first extract to our own directory where we have full rights to write to
                        let tempUrl = try await engine.extract(
                            item: item,
                            from: archiveUrl,
                            to: temp.url
                        )
                        
                        // guard the extracted url
                        guard let tempUrl else {
                            Logger.error("Could not get url for extracted file")
                            return
                        }
                        
                        // then move the file to the actual target... This is required
                        // because in case of a file promise we only get access to write
                        // to the file, but not to the directory where the file is being
                        // dragged to.
                        
                        let targetUrl = destination.appending(component: item.name)
                        
                        let _ = destination.startAccessingSecurityScopedResource()
                        defer { destination.stopAccessingSecurityScopedResource() }
                        
                        Logger.debug("Extraction successful. Now moving \(tempUrl) to \(targetUrl) at destination \(destination)")
                        
                        try FileManager.default.moveItem(
                            at: tempUrl,
                            to: targetUrl)
                    }
                }
            } catch {
                Logger.error(error)
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isBusy = false
                }
            }
        }
    }
    
    public func extract(to destination: URL) {
        Task {
            do {
                guard let root else {
                    Logger.error("No root item set")
                    return
                }
                
                if let (archiveTypeId, archiveUrl) = findHandlerAndUrl(for: root),
                   let engine = archiveEngineSelector.engine(for: archiveTypeId) {
                    
                    let _ = destination.startAccessingSecurityScopedResource()
                    defer { destination.stopAccessingSecurityScopedResource() }
                    
                    // first extract to our own directory where we have full rights to write to
                    try await engine.extract(
                        archiveUrl,
                        to: destination
                    )
                }
            } catch {
                Logger.error(error)
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isBusy = false
                }
            }
        }
    }
    
    public func clean() {
        
    }
    
    public func openParent() {
        if selectedItem?.type == .root {
            return
        }
        
        let previousItem = selectedItem
        
        selectedItem = selectedItem?.parent
        
        self.isReloadNeeded = true
        
        if let previousItem {
            self.selectedItems = [previousItem]
        } else {
            self.selectedItems = []
        }
    }
    
    /// Updates the quick look preview URL. The previewer we're using is the default systems
    /// preview that is called Quick Look and that can be reached via Space in Finder
    ///
    /// When Space is pressed by the user while any item is selected, we're opening this default
    /// preview to support any file type that is supported by the system anyways. This might
    /// also override any previously selected item in which case quick look will just adopt.
    ///
    /// In case no item is selected then set the preview url to nil to make sure Quick Look is closing.
    public func updateSelectedItemForQuickLook() {
        Task {
            if let selectedItem = self.selectedItems.first,
               let (archiveTypeId, archiveUrl) = findHandlerAndUrl(for: selectedItem),
               let temp = createTempDirectory(),
               let engine = archiveEngineSelector.engine(for: archiveTypeId) {
                let url = try await engine.extract(
                    item: selectedItem,
                    from: archiveUrl,
                    to: temp.url
                )
                self.previewItemUrl = url
            } else if self.selectedItems.isEmpty {
                self.previewItemUrl = nil
            }
        }
    }
    
    public func changeSelection(selection: IndexSet) {
        Logger.log("Selection changed: tableViewSelectionDidChange(_:)")
        
        guard let selectedItem else { return }
        let hasParent = selectedItem.type != .root
        
        // Adjust selection to account for parent row when present
        var adjustedSelection: IndexSet? = selection
        if hasParent {
            // Shift each selected index down by 1 to skip the parent row (at index 0)
            let shifted = selection.compactMap { idx -> Int? in
                let v = idx - 1
                return v >= 0 ? v : nil
            }
            adjustedSelection = IndexSet(shifted)
        }
        
        if let indexes = adjustedSelection,
           let children = selectedItem.children {
            
            selectedItems.removeAll()
            for index in indexes {
                let archiveItem = children[index]
                selectedItems.append(archiveItem)
            }
            
            // in case quick look is open right now, then change the
            // previewed item
            if previewItemUrl != nil {
                updateSelectedItemForQuickLook()
            }
        }
    }
    
    //
    // MARK: General Async
    //
    // The methods below do the actual work in a Swift 6 concurrency safe way.
    // Those are not called from the UI, but rather from the unit tests
    // directly to ensure that the unit tests can run properly.
    //
    
    
    
    public func openAsync(item: ArchiveItem) async throws {
        switch item.type {
        case .file:
            // If it is a file, check first if it has children > this can
            // only happen if the file is an archive and if the archive
            // was temporarily extracted before
            if item.children != nil {
                // Do nothing here. It is an archive. It is extracted already.
                // We have updated the hierarchy already. Just select the item
                selectedItem = item
            }

            // If the children is nil, then we need to figure out if this
            // is an archive that we actually support, or whether it is
            // a regular file.
            //
            // 1. Regular File: Open the file using the system default editor
            // 2. Archive File: Extract the archive to a temporary internal
            //                  location, and extend the hiearchy accordingly.
            //                  Then set the item.
            if item.children == nil {
                // walk up the hierarchy of the item to check if there is any
                // handler responsible for it because the item is in a nested
                // archive, otherwise, use the main archives handler to extract the item
                
                if let tempUrl = try await extractAsync(item: item) {

                    // We check by extension here because we don't want to end up
                    // opening files like .xlsx as an archive. An Excel file (or any
                    // other archived file that is basically a .zip file) should be
                    // extracted and treated like an Excel file instead of an archive
                    //
                    // TODO: Add the possibility via right click menu in MacPacker
                    //       to open the file as archive instead.
                    // TODO: considerComposition result should be true here
                    if let detectionResult = archiveTypeDetector.detectByExtension(for: tempUrl, considerComposition: false),
                       let engine = archiveEngineSelector.engine(for: detectionResult.type.id) {
                        
                        // set the services required for this nested archive
                        item.set(
                            url: tempUrl,
                            typeId: detectionResult.type.id
                        )

                        // nested archive is extracted > time to parse its hierarchy
                        try await unfold(item, using: engine)
//                        let entries = try await engine.loadArchive(url: tempUrl)
//                        buildTree(for: entries, at: archiveItem)
//                        ArchiveHierarchyPrinter().printHierarchy(item: archive.rootNode)

                        // set the nested archive as item
                        selectedItem = item
                    } else {
                        // Could not detect any archive, just open the file
                        NSWorkspace.shared.open(tempUrl)
                    }
                }
            }
            break
        case .archive:
            break
        case .root:
            // cannot happen as this never shows up
            break
        case .directory:
            selectedItem = item
            break
        case .unknown:
            Logger.error("Unhandled ArchiveItem.Type: \(item.name)")
            break
        }
    }
    
    /// This will extract the given item from the archive to a temporary destination
    /// - Parameter archiveItem: item to extract
    /// - Returns: the url of the extracted file when successful
    public func extractAsync(item: ArchiveItem) async throws -> URL? {
        // We need to figure out first which archive actually contains
        // the currently selected file. Is it the root archive, or is
        // it a nested archive?
        
        guard let temp = createTempDirectory() else {
            Logger.error("Could not create temp directory for extraction")
            return nil
        }
        
        if let (archiveTypeId, archiveUrl) = findHandlerAndUrl(for: item),
           let engine = archiveEngineSelector.engine(for: archiveTypeId) {
            
            let url = try await engine.extract(
                item: item,
                from: archiveUrl,
                to: temp.url
            )
            
            return url
        }
        
        return nil
    }
    
    public func createTempDirectory() -> (id: String, url: URL)? {
        do {
            let applicationSupport = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            let id = UUID().uuidString
            let appSupportSubDirectory = applicationSupport
                .appendingPathComponent("ta", isDirectory: true)
                .appendingPathComponent(id, isDirectory: true)
            try FileManager.default.createDirectory(at: appSupportSubDirectory, withIntermediateDirectories: true, attributes: nil)
            print(appSupportSubDirectory.path) // /Users/.../Library/Application Support/YourBundleIdentifier
            return (id, appSupportSubDirectory)
        } catch {
            print(error)
        }
        return nil
    }
    
    private func findHandlerAndUrl(for archiveItem: ArchiveItem) -> (String, URL)? {
        var item: ArchiveItem? = archiveItem
        var url: URL?
        var typeId: String?
    
        while item != nil {
            if item?.archiveTypeId != nil && item?.url != nil {
                url = item?.url
                typeId = item?.archiveTypeId
                break
            }
            item = item?.parent
        }
        
        guard let url, let typeId else { return nil }
    
        return (typeId, url)
    }
    
    /// Checks if the given archive extension is supported to be loaded in MacPacker
    /// - Parameter url: url to the archive in question
    /// - Returns: true in case supported, false otherwise
    public func isSupportedArchive(url: URL) -> Bool {
//        return ArchiveTypeRegistry.shared.isSupported(url: url)
        return true
    }
}

