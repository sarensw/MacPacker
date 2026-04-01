//
//  ArchiveState.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 04.05.25.
//

import Combine
import Foundation
import SwiftUI

public enum ArchiveStateStatus: String {
    case idle
    case processing
    case done
}

@MainActor
public class ArchiveState: ObservableObject {
    // MARK: UI
    // Basic archive metadata
    @Published private(set) public var url: URL?
    @Published private(set) public var name: String?
    @Published private(set) public var type: ArchiveTypeDto?
    @Published private(set) public var compositionType: CompositionTypeDto?
    @Published private(set) public var ext: String?
    @Published private(set) public var uncompressedSize: Int64?
    @Published private(set) public var isEncrypted: Bool? = false
    
    // Full list of entries
    @Published private(set) public var entries: [UUID: ArchiveItem] = [:]
    
    // Root item
    @Published private(set) public var root: ArchiveItem?
    
    // Currently selected item (i.e. its children are shown in the
    // table of the archive view
    @Published private(set) public var selectedItem: ArchiveItem?
    @Published private(set) public var childItems: [ArchiveItem]?
    private var currentSortOrder: NSSortDescriptor? = nil
    
    // Items currently selected by the user in the tree / table
    @Published public var selectedItems: [ArchiveItem] = []
    
    // UI State
    @Published private(set) public var isBusy: Bool = false
    @Published private(set) public var statusText: String? = nil
    @Published private(set) public var progress: Int? = nil
    @Published private(set) public var error: String? = nil
    @Published public var isReloadNeeded: Bool = false
    
    // Listeners for non-ui
    @Published private(set) public var status: ArchiveStateStatus = .idle
    public var onStatusChange: ((ArchiveStateStatus) -> Void)?
    public var onStatusTextChange: ((String?) -> Void)?
    
    // TODO: Still needed?
    @Published public var openWithUrls: [URL] = []
    @Published public var previewItemUrl: URL?
    
    private let catalog: ArchiveTypeCatalog
    private let archiveEngineSelector: ArchiveEngineSelectorProtocol
    private let archiveTypeDetector: ArchiveTypeDetector
    
    private var tempDirectories: [URL] = []
    
    public var passwordProvider: ArchivePasswordUserProvider?
    private var passwords: [URL: String] = [:]
    
    public private(set) var openTask: Task<Void, any Error>?
    private var archiveLoader: ArchiveLoader?
    
    public init(catalog: ArchiveTypeCatalog, engineSelector: ArchiveEngineSelectorProtocol) {
        self.catalog = catalog
        self.archiveEngineSelector = engineSelector
        self.archiveTypeDetector = ArchiveTypeDetector(catalog: catalog)
    }
}

extension ArchiveState {
    
    private func makePasswordResolver() -> ArchivePasswordResolver {
        return { @MainActor [weak self] request in
            guard let self else { return nil }
            
            // see if we have the password cached already
            if let password = passwords[request.url] {
                return password
            }
            
            // if not cached, ask the user to provide the password
            let password = await self.passwordProvider?(request)
            if let password {
                self.passwords[request.url] = password
            }
            
            return password
        }
    }
    
    private func updateStatus(_ status: ArchiveStateStatus) {
        if status == .done {
            onStatusChange?(.done)
            updateStatus(.idle)
            return
        }
        self.status = status
        onStatusChange?(status)
    }
    
    private func updateStatusText(_ text: String?) {
        self.statusText = text
        onStatusTextChange?(text)
    }
    
    /// Resets the state of the archive
    private func reset() {
        self.url = nil
        self.name = nil
        self.type = nil
        self.compositionType = nil
        self.ext = nil
        self.uncompressedSize = nil
        self.isEncrypted = nil
        
        self.root = nil
        
        updateStatusText(nil)
        
        self.isBusy = false
        self.isReloadNeeded = true
        
        self.selectedItem = nil
        self.selectedItems = []
        
        self.childItems = nil
        self.currentSortOrder = nil
        
        self.archiveLoader = nil
        
        self.passwords = [:]
        
        updateStatus(.idle)
        
        CacheCleaner().clean(tempDirectories: tempDirectories)
    }
    
    public func clean() {
        reset()
    }
    
    /// Cancels the current operation which can be either loading the archive or extracting
    /// anything from the archive
    public func cancelCurrentOperation() {
        openTask?.cancel()
        Task {
            await archiveLoader?.cancel()
            archiveLoader = nil
            
            reset()
        }
    }
    
    public func loadChildren(sortedBy: NSSortDescriptor? = nil) {
        guard let selectedItem else { return }
        guard let sortedBy else {
            childItems = selectedItem.children?.compactMap { entries[$0] }
            currentSortOrder = nil
            return
        }
        
        if let children = selectedItem.children?.compactMap({ entries[$0] }) {
            currentSortOrder = sortedBy

            childItems = children.sorted { a, b in
                if a.type != b.type { return a.type == .directory }

                let cmp = a.name.localizedStandardCompare(b.name)
                if sortedBy.ascending {
                    return cmp == .orderedAscending
                } else {
                    return cmp == .orderedDescending
                }
            }
        }
    }
    
    /// This stream is the only way to get status from any engine in a concurrency safe way
    /// - Parameter stream: the stream from the engine
    /// - Returns: handler task that can be used for different actions like loading, extracting, ...
    private func receiveStatusUpdates(from stream: AsyncStream<EngineStatus>) -> Task<Void, Never> {
        let statusTask = Task {
            for await status in stream {
                switch status {
                case .cancelled:
                    updateStatusText(nil)
                    self.progress = nil
                    print("cancelled")
                case .idle:
                    updateStatusText(nil)
                    self.progress = nil
                    print("idle")
                case .processing(let progress, let message):
                    updateStatusText(message)
                    if progress != nil {
                        self.progress = Int(progress!)
                    }
                case .done:
                    updateStatusText("done")
                    self.progress = nil
                    print("done")
                case .error(let error):
                    updateStatusText("error: \(error.localizedDescription)")
                    self.progress = nil
                    print("error: \(error.localizedDescription)")
                }
            }
        }
        return statusTask
    }
    
    //
    // MARK: Open
    //
    
    /// Opens the given url.
    /// - Parameter url: url of the archiver to open
    public func open(url: URL) {
        reset()
        updateStatus(.processing)
        
        self.isBusy = true
        self.error = nil
        self.url = url
        self.name = url.lastPathComponent
        self.ext = url.pathExtension
        
        openTask = Task {
            do {
                let passwordResolver = makePasswordResolver()
                let archiveLoader = ArchiveLoader(
                    archiveTypeDetector: self.archiveTypeDetector,
                    archiveEngineSelector: self.archiveEngineSelector,
                    passwordResolver: passwordResolver
                )
                self.archiveLoader = archiveLoader
                
                let stream = await archiveLoader.statusStream()
                let statusTask = receiveStatusUpdates(from: stream)
                defer { statusTask.cancel() }
                
                updateStatusText("loading...")
                let loaderResult = try await archiveLoader.loadEntries(url: url)
                // why does root have itself as child here?
                if let tempDirectory = loaderResult.tempDirectory {
                    tempDirectories.append(tempDirectory)
                }
                
                try Task.checkCancellation()
                
                if loaderResult.error != nil {
                    updateStatusText("failed to load")
                    self.error = loaderResult.error
                }
                self.root = loaderResult.root
                self.selectedItem = loaderResult.root
                
                self.type = loaderResult.type
                self.compositionType = loaderResult.compositionType
                self.uncompressedSize = loaderResult.uncompressedSize
                
                updateStatusText("building tree...")
                
                try Task.checkCancellation()
                
                if !loaderResult.hasTree {
                    let builderResult = await archiveLoader.buildTree(at: loaderResult.root)
                    self.error = builderResult.error
                }
                self.entries.merge(loaderResult.entries, uniquingKeysWith: { lhs, _ in lhs })
                self.entries[loaderResult.root.id] = root
                
                loadChildren(sortedBy: currentSortOrder)
                
                updateStatusText(nil)
                
                self.selectedItems = []
                
                self.isBusy = false
                self.isReloadNeeded = true
                self.archiveLoader = nil
                
                try Task.checkCancellation()
            } catch is CancellationError {
                reset()
            } catch {
                reset()
                self.error = error.localizedDescription
            }
            
            updateStatus(.done)
        }
    }
    
    public func open(item: ArchiveItem) {
        Task {
            do {
                try await openAsync(item: item)
            } catch {
                self.error = error.localizedDescription
                
                self.isBusy = false
                self.isReloadNeeded = true
                self.selectedItems = []
                
                updateStatusText(nil)
                updateStatus(.done)
            }
        }
    }
    
    public func openAsync(item: ArchiveItem) async throws {
        updateStatus(.processing)
        
        switch item.type {
        case .file:
            // If it is a file, check first if it has children > this can
            // only happen if the file is an archive and if the archive
            // was temporarily extracted before
            if item.children == nil {
                // If the children is nil, then we need to figure out if this
                // is an archive that we actually support, or whether it is
                // a regular file.
                //
                // 1. Regular File: Open the file using the system default editor
                // 2. Archive File: Extract the archive to a temporary internal
                //                  location, and extend the hiearchy accordingly.
                //                  Then set the item.
                self.isBusy = true
                self.error = nil
                updateStatusText("extracting...")
                
                try await openFile(item)
            } else {
                // Do nothing here. It is an archive. It is extracted already.
                // We have updated the hierarchy already. Just select the item
                self.selectedItem = item
                loadChildren(sortedBy: currentSortOrder)
            }
        case .archive:
            // TODO: This can never happen as each archive is also of type .file > Remove .archive as a type
            break
        case .virtual:
            self.selectedItem = item
            loadChildren(sortedBy: currentSortOrder)
            break
        case .directory:
            self.selectedItem = item
            loadChildren(sortedBy: currentSortOrder)
            break
        case .root:
            self.selectedItem = item
            loadChildren(sortedBy: currentSortOrder)
            break
        case .unknown:
            Logger.error("Unhandled ArchiveItem.Type: \(item.name)")
            break
        }
        
        self.isBusy = false
        self.isReloadNeeded = true
        self.selectedItems = []
        
        updateStatusText(nil)
        updateStatus(.done)
    }
    
    /// Opens the parent of the current view
    public func openParent() {
        updateStatus(.processing)
        
        if selectedItem?.type == .root {
            updateStatus(.done)
            return
        }
        
        let previousItem = selectedItem
        
        selectedItem = entries.first(where: { $0.key == selectedItem?.parent })?.value
        loadChildren(sortedBy: currentSortOrder)
        
        self.isReloadNeeded = true
        
        if let previousItem {
            self.selectedItems = [previousItem]
        } else {
            self.selectedItems = []
        }
        
        updateStatus(.done)
    }
    
    /// Opens an item upon double click (typical use case). When the double clicked item is
    /// an archive that we know, we're extracting it into a temp folder and extending our current tree
    /// and show the content seamlessly in the archive window. If this is a regular file, we're extracting
    /// it still, but also open the file using the system editor.
    ///
    /// NOTE: The item has to be a .file.
    ///
    /// - Parameter item: file to open
    public func openFile(_ item: ArchiveItem) async throws {
        // Extract the item first as we have to either open it in the system
        // default preview or treat it as an archive
        let passwordResolver = makePasswordResolver()
        let archiveExtractor = ArchiveExtractor(
            archiveEngineSelector: self.archiveEngineSelector,
            passwordResolver: passwordResolver
        )
        let batchResolver = ArchiveBatchResolver()
        guard let batch = try batchResolver.resolveBatches(for: [item], in: entries, using: self.archiveEngineSelector).first else {
            throw ArchiveError.extractionFailed("Could not resolve batch for extraction")
        }
        let archiveExtractionResult = try await archiveExtractor.extract(
            batch: batch
        )
        let tempDir = archiveExtractionResult.tempDir
        let tempUrl = archiveExtractionResult.url
            
        tempDirectories.append(tempDir)
        // We check by extension here because we don't want to end up
        // opening files like .xlsx as an archive. An Excel file (or any
        // other archived file that is basically a .zip file) should be
        // extracted and treated like an Excel file instead of an archive
        //
        // TODO: Add the possibility via right click menu in MacPacker
        //       to open the file as archive instead.
        var detectUsingExtensionOnly = true
        if self.type?.id == "pkg" {
            detectUsingExtensionOnly = false
        }
        
        if let detectionResult = (detectUsingExtensionOnly
            ? archiveTypeDetector.detectByExtension(for: tempUrl, considerComposition: true)
            : archiveTypeDetector.detect(for: tempUrl, considerComposition: true)),
           let engine = archiveEngineSelector.engine(for: detectionResult.type.id) {
            
            // set the services required for this nested archive
            item.set(
                url: tempUrl,
                typeId: detectionResult.type.id
            )

            // nested archive is extracted > time to parse its hierarchy
            try await unfold(item, using: engine)

            // set the nested archive as item
            selectedItem = item
            loadChildren(sortedBy: currentSortOrder)
        } else {
            // Could not detect any archive, just open the file
            NSWorkspace.shared.open(tempUrl)
        }
    }
    
    /// This func is called with an item that is an archive (typed as .file, but detected as supported
    /// archive) to be unfold in the sense that its hiearchy is loaded into the given hierarchy.
    /// - Parameters:
    ///   - archiveItem: item to load as archive
    ///   - engine: engine to use
    private func unfold(_ archiveItem: ArchiveItem, using engine: ArchiveEngine) async throws {
        if let url = archiveItem.url {
            self.isBusy = true
            self.error = nil
            self.name = url.lastPathComponent
            self.ext = url.pathExtension
            
            do {
                let passwordResolver = makePasswordResolver()
                let archiveLoader = ArchiveLoader(
                    archiveTypeDetector: self.archiveTypeDetector,
                    archiveEngineSelector: self.archiveEngineSelector,
                    passwordResolver: passwordResolver
                )
                
                let stream = await archiveLoader.statusStream()
                let statusTask = receiveStatusUpdates(from: stream)
                defer { statusTask.cancel() }
                
                updateStatusText("loading...")
                let loaderResult = try await archiveLoader.loadEntries(url: url)
                
                if let tempDirectory = loaderResult.tempDirectory {
                    tempDirectories.append(tempDirectory)
                }
                
                if loaderResult.error != nil {
                    updateStatusText("failed to load")
                    self.error = loaderResult.error
                }
                self.selectedItem = archiveItem
                
                updateStatusText("building tree...")
                
                if !loaderResult.hasTree {
                    let builderResult = await archiveLoader.buildTree(at: archiveItem)
                    self.error = builderResult.error
                }
                self.entries.merge(loaderResult.entries) { (current, _) in current }
                
                loadChildren(sortedBy: currentSortOrder)
                
                updateStatusText(nil)
                
                self.isBusy = false
                self.isReloadNeeded = true
                self.selectedItems = []
            } catch {
                self.error = error.localizedDescription
                self.isBusy = false
            }
        }
    }
    
    //
    // MARK: Extraction
    //
    
    /// Extracts the given item (file) to a temporary location return the url
    /// - Parameter item: item to extract
    /// - Returns: url of the extracted item in the temp location
    public func extractToTemp(item: ArchiveItem) async throws -> URL {
        let batchResolver = ArchiveBatchResolver()
        let batches = try batchResolver.resolveBatches(for: [item], in: entries, using: archiveEngineSelector)
        guard let batch = batches.first else {
            throw ArchiveError.extractionFailed("Could not resolve batch")
        }
        let extractor = ArchiveExtractor(
            archiveEngineSelector: archiveEngineSelector,
            passwordResolver: makePasswordResolver()
        )
        let result = try await extractor.extract(batch: batch)
        tempDirectories.append(result.tempDir)
        return result.url
    }
    
    /// Extracts the given set of items to the given destination. This is usually triggered by the
    /// user from within the UI
    /// - Parameters:
    ///   - items: items to extract
    ///   - destination: destination folder
    public func extract(
        items: [ArchiveItem],
        to destination: URL
    ) {
        updateStatus(.processing)
        
        let extractor = ArchiveExtractor(
            archiveEngineSelector: archiveEngineSelector,
            passwordResolver: makePasswordResolver()
        )
        let batchResolver = ArchiveBatchResolver()
        
        Task {
            do {
                let batches = try batchResolver.resolveBatches(for: items, in: entries, using: archiveEngineSelector)
                let result = try await extractor.extract(
                    batches: batches,
                    to: destination
                )
                tempDirectories.append(contentsOf: result.tempDirs)
            } catch {
                Logger.error(error)
                self.error = error.localizedDescription
                self.isBusy = false
            }
            
            updateStatus(.done)
        }
    }
    
    public func extract(to destination: URL) {
        isBusy = true
        updateStatus(.processing)
        
        Task {
            do {
                guard let root else {
                    Logger.error("No root item set")
                    return
                }
                
                if let (archiveTypeId, archiveUrl) = ArchiveSupportUtilities().findHandlerAndUrl(for: root, in: entries) {
                    let extractor = ArchiveExtractor(
                        archiveEngineSelector: archiveEngineSelector,
                        passwordResolver: makePasswordResolver()
                    )
                    try await extractor.extractAll(archiveUrl, archiveTypeId: archiveTypeId, to: destination)
                }
            } catch {
                Logger.error(error)
                self.error = error.localizedDescription
                self.isBusy = false
            }
            
            updateStatus(.done)
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
        updateStatus(.processing)
        
        let extractor = ArchiveExtractor(
            archiveEngineSelector: archiveEngineSelector,
            passwordResolver: makePasswordResolver()
        )
        let batchResolver = ArchiveBatchResolver()
        Task {
            do {
                if
                    let selectedItem = self.selectedItems.first,
                    let batch = try batchResolver.resolveBatches(
                        for: [selectedItem],
                        in: entries,
                        using: archiveEngineSelector
                    ).first
                {
                    
                    let result = try await extractor.extract(
                        batch: batch
                    )
                    
                    tempDirectories.append(result.tempDir)
                    
                    self.previewItemUrl = result.url
                    
                } else if self.selectedItems.isEmpty {
                    self.previewItemUrl = nil
                }
            } catch {
                Logger.error(error)
                self.error = error.localizedDescription
                self.isBusy = false
            }
            
            updateStatus(.done)
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
           let children = childItems {
            
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
    
    public func selectionOffset(selection: IndexSet) -> IndexSet {
        guard let selectedItem else { return selection }
        let hasParent = selectedItem.type != .root
        
        var adjustedSelection: IndexSet = selection
        if hasParent {
            let shifted = selection.compactMap { idx -> Int? in
                let v = idx + 1
                return v < 0 ? nil : v
            }
            adjustedSelection = IndexSet(shifted)
        } else {
            adjustedSelection = selection
        }
        
        return adjustedSelection
    }
}

