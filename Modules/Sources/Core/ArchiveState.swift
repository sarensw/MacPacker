//
//  ArchiveState.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 04.05.25.
//

import Combine
import Foundation
import Swift7zip
import SwiftUI
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "archive")
private let extractLog = tb.Logger(subsystem: "app.MacPacker", category: "extraction")
private let passwordLog = tb.Logger(subsystem: "app.MacPacker", category: "password")

public enum ArchiveStateStatus: String {
    case idle
    case processing
    case done
}

public enum ArchiveSortOrder: String {
    case name
    case compressedSize
    case uncompressedSize
    case modificationDate
    case posixPermissions
}

/// What the status bar should communicate while a file is dragged over the window.
/// The UI maps each case to a localized, styled hint.
public enum ArchiveDropHint: Equatable, Sendable {
    /// A file is over the window with no modifier held — teach the ⌥ affordance.
    case dragging
    /// ⌥ is held — releasing will open the file in a new window.
    case openInNewWindow
}

@MainActor
public class ArchiveState: ObservableObject {
    @Published private(set) public var hasArchive: Bool = false
    @Published private(set) public var canBeEdited: Bool = false
    /// True from the moment a save starts until the archive has been rewritten
    /// and reloaded. While set, all mutating actions (add / delete / save) are
    /// refused so the archive can't change under the in-flight write.
    @Published private(set) public var isSaving: Bool = false
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
    @Published private(set) public var diff: [ArchiveUpdateItem] = []

    /// Number of real items in the archive (files + directories across all
    /// levels), excluding the synthetic `<root>` node that `entries` also holds.
    public var itemCount: Int {
        entries.values.reduce(into: 0) { count, item in
            if item.type != .root { count += 1 }
        }
    }
    
    // Root item
    @Published private(set) public var root: ArchiveItem?
    
    // Currently selected item (i.e. its children are shown in the
    // table of the archive view
    @Published private(set) public var selectedItem: ArchiveItem?
    @Published private(set) public var childItems: [ArchiveItem]?
    
    // Items currently selected by the user in the tree / table
    @Published public var selectedItems: [ArchiveItem] = []
    
    // UI State
    @Published private(set) public var isBusy: Bool = false
    @Published private(set) public var statusText: String? = nil
    @Published private(set) public var progress: Int? = nil
    @Published private(set) public var error: String? = nil
    @Published public var isReloadNeeded: Bool = false
    /// Transient state shown in the status bar while a file is dragged over the
    /// window. nil when no drag is active — the normal status-bar info shows then.
    @Published public var dropHint: ArchiveDropHint? = nil

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
    public var folderAccessProvider: ArchiveFolderAccessUserProvider?
    /// Hands a plain (non-archive) file to the system after extraction. The app
    /// wires this to `NSWorkspace.shared.open`; the default is a no-op so Core
    /// carries no AppKit dependency and unit tests never launch an external app.
    public var openFileExternally: (URL) -> Void = { _ in }
    /// Where user-triggered extractions report their progress. Defaults to
    /// the app-wide center that feeds the extraction progress window;
    /// tests inject their own instance.
    public var progressCenter: ExtractionProgressCenter = .shared
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
            passwordLog.info("Password requested", context: ["archive": request.url.lastPathComponent])
            let password = await self.passwordProvider?(request)
            if let password {
                self.passwords[request.url] = password
                passwordLog.info("Password accepted", context: ["archive": request.url.lastPathComponent])
            } else {
                passwordLog.notice("Password entry cancelled", context: ["archive": request.url.lastPathComponent])
            }
            
            return password
        }
    }

    private func makeFolderAccessResolver() -> ArchiveFolderAccessResolver {
        return { @MainActor [weak self] fileURL in
            guard let self, let provider = self.folderAccessProvider else { return false }
            return await provider(fileURL)
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
        self.hasArchive = false
        
        self.url = nil
        self.name = nil
        self.type = nil
        self.compositionType = nil
        self.ext = nil
        self.uncompressedSize = nil
        self.isEncrypted = nil
        self.diff = []

        self.root = nil
        // A reopen (e.g. after saving) reloads with fresh UUID-keyed entries.
        // Without clearing here the previous load's entries linger and merge
        // in, inflating counts and the tree — reset is a full teardown.
        self.entries = [:]

        updateStatusText(nil)
        
        self.isBusy = false
        self.isReloadNeeded = true
        
        self.selectedItem = nil
        self.selectedItems = []
        
        self.childItems = nil
        
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
    
    public func loadChildren() {
        guard let selectedItem else { return }
        
        let defaultOrderColumn = UserDefaults.standard.string(forKey: Keys.defaultOrderColumn)
        let defaultOrderColumnAscending = UserDefaults.standard.bool(forKey: Keys.defaultOrderColumnAscending)
        
        guard defaultOrderColumn != nil else {
            childItems = selectedItem.children?.compactMap { entries[$0] }
            return
        }
        
        if let children = selectedItem.children?.compactMap({ entries[$0] }) {
            childItems = children.sorted { a, b in
                switch defaultOrderColumn {
                case ArchiveSortOrder.name.rawValue:
                    if a.type != b.type {
                        return a.type == .directory
                    }

                    let cmp = a.name.localizedStandardCompare(b.name)
                    return defaultOrderColumnAscending ? cmp == .orderedAscending : cmp == .orderedDescending

                case ArchiveSortOrder.modificationDate.rawValue:
                    let lhs = a.modificationDate ?? .distantPast
                    let rhs = b.modificationDate ?? .distantPast
                    
                    return defaultOrderColumnAscending
                    ? lhs < rhs
                    : lhs > rhs

                case ArchiveSortOrder.uncompressedSize.rawValue:
                    return defaultOrderColumnAscending
                    ? a.uncompressedSize < b.uncompressedSize
                    : a.uncompressedSize > b.uncompressedSize
                    
                case ArchiveSortOrder.compressedSize.rawValue:
                    return defaultOrderColumnAscending
                    ? a.compressedSize < b.compressedSize
                    : a.compressedSize > b.compressedSize
                    
                case ArchiveSortOrder.posixPermissions.rawValue:
                    let lhs = a.posixPermissions ?? 0
                    let rhs = b.posixPermissions ?? 0
                    
                    return defaultOrderColumnAscending
                    ? lhs < rhs
                    : lhs > rhs

                default:
                    return false
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
                    log.debug("status: cancelled")
                case .idle:
                    updateStatusText(nil)
                    self.progress = nil
                    log.debug("status: idle")
                case .processing(let progress, let message):
                    updateStatusText(message)
                    if progress != nil {
                        self.progress = Int(progress!)
                    }
                case .done:
                    updateStatusText("done")
                    self.progress = nil
                    log.debug("status: done")
                case .error(let error):
                    updateStatusText("error: \(error.localizedDescription)")
                    self.progress = nil
                    log.error("engine status error", context: ["error": error.localizedDescription])
                }
            }
        }
        return statusTask
    }
    
    /// Checks if the given URL is an archive that we support
    /// - Parameter url: url to check
    /// - Returns: true in case it is a supported archive, false otherwise
    public func isSupportedArchive(url: URL) -> Bool {
        return archiveTypeDetector.detect(for: url) != nil
    }
    
    //
    // MARK: Create / Edit
    //
    
    public func create() {
        reset()
        
        self.canBeEdited = true
        self.hasArchive = true
        // self.url = nil
        self.name = "New Archive"
        self.type = self.catalog.getType(for: "zip")
        self.ext = ".zip"
        
        self.root = ArchiveItem(name: "<root>", virtualPath: "/", type: .root)
        
        self.isReloadNeeded = true
        
        self.selectedItem = root
        loadChildren()
    }
    
    public func add(url: URL) {
        guard !isSaving else {
            log.notice("Ignoring add — a save is in progress", context: ["file": url.lastPathComponent])
            return
        }
        guard let selectedItem else { return }
        let base = (selectedItem.virtualPath?.isEmpty == false && selectedItem.virtualPath != "/")
            ? selectedItem.virtualPath! + "/" : ""

        if url.isDirectory {
            // folders are added recursively so their contents end up in the archive
            addFolder(url: url, archivePath: base + url.lastPathComponent, under: selectedItem)
        } else {
            addFile(url: url, archivePath: base + url.lastPathComponent, under: selectedItem)
        }

        self.isReloadNeeded = true
        loadChildren()
    }

    private func addFile(url: URL, archivePath: String, under parent: ArchiveItem) {
        diff.append(.addFile(archivePath: archivePath, diskPath: url))
        let item = ArchiveItem(url: url, archivePath: archivePath)
        item.parent = parent.id
        parent.addChild(item.id)
        entries[item.id] = item
    }

    private func addFolder(url: URL, archivePath: String, under parent: ArchiveItem) {
        // Read the contents first: if the folder can't be enumerated we must not
        // add it as an empty directory (that would silently drop its real
        // contents on save). Skip it and surface the error instead.
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil)
        } catch {
            log.error("Failed to read folder for add — skipping", context: [
                "path": url.path,
                "error": String(describing: error)
            ])
            self.error = error.localizedDescription
            return
        }

        diff.append(.addDirectory(archivePath: archivePath))
        let item = ArchiveItem(url: url, archivePath: archivePath)
        item.parent = parent.id
        parent.addChild(item.id)
        entries[item.id] = item

        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if child.isDirectory {
                addFolder(url: child, archivePath: archivePath + "/" + child.lastPathComponent, under: item)
            } else {
                addFile(url: child, archivePath: archivePath + "/" + child.lastPathComponent, under: item)
            }
        }
    }

    /// Removes the given items (files or folders, including everything below
    /// them) from the archive. The removal is recorded in the diff — `save()`
    /// applies it to the file.
    public func remove(items: [ArchiveItem]) {
        guard canBeEdited else { return }
        guard !isSaving else {
            log.notice("Ignoring delete — a save is in progress", context: ["items": "\(items.count)"])
            return
        }

        var removedIndices: Set<UInt32> = []
        var droppedAddPaths: Set<String> = []
        for item in items {
            collectRemovals(item, indices: &removedIndices, pendingPaths: &droppedAddPaths)
            if let parentId = item.parent {
                entries[parentId]?.removeChild(item.id)
            }
        }

        // pending (unsaved) additions are simply dropped from the diff
        if !droppedAddPaths.isEmpty {
            diff.removeAll { entry in
                switch entry {
                case .addFile(let p, _, _, _), .addDirectory(let p, _, _), .addData(let p, _, _, _):
                    return droppedAddPaths.contains(p)
                default:
                    return false
                }
            }
        }
        // entries that exist in the archive on disk are removed on save
        diff.append(contentsOf: removedIndices.sorted().map { .remove(sourceIndex: $0) })

        log.notice("Marked items for removal", context: [
            "items": "\(items.count)",
            "archiveEntries": "\(removedIndices.count)",
            "pendingAdds": "\(droppedAddPaths.count)"
        ])

        selectedItems = []
        isReloadNeeded = true
        loadChildren()
    }

    /// Depth-first: collects the source indices (real archive entries) and
    /// pending-addition paths of the item and all of its descendants, and
    /// drops them from `entries`.
    private func collectRemovals(
        _ item: ArchiveItem,
        indices: inout Set<UInt32>,
        pendingPaths: inout Set<String>
    ) {
        for childId in item.children ?? [] {
            if let child = entries[childId] {
                collectRemovals(child, indices: &indices, pendingPaths: &pendingPaths)
            }
        }
        if let index = item.index {
            indices.insert(index)
        } else if let path = item.virtualPath, path != "/" {
            pendingPaths.insert(path)
        }
        entries.removeValue(forKey: item.id)
    }

    /// Opens a dropped file in this window: a supported archive is opened directly;
    /// anything else becomes the first entry of a new archive. `open`/`create` reset
    /// the state, so this replaces whatever is currently loaded.
    public func openDropped(url: URL) {
        if isSupportedArchive(url: url) {
            open(url: url)
        } else {
            create()
            add(url: url)
        }
    }

    /// Whether there are unsaved changes (pending additions/removals).
    public var hasPendingChanges: Bool { !diff.isEmpty }

    /// Saves the pending changes.
    ///
    /// - For an archive loaded from disk, the changes are applied in place
    ///   (`destination` may override, "save as").
    /// - For a new archive (never saved), `destination` is required — that's
    ///   where the archive is created.
    ///
    /// After a successful write the archive is reloaded from disk so the
    /// shown entries (and their source indices) match the file again.
    @discardableResult
    public func save(
        to destination: URL? = nil,
        options: SevenZipCompressionOptions? = nil
    ) -> Task<Void, Never>? {
        guard !isSaving else {
            log.notice("Ignoring save — a save is already in progress")
            return nil
        }
        guard let target = destination ?? url else { return nil }
        guard !diff.isEmpty else { return nil }

        let source = url
        let items = diff
        // format follows the target extension; zip is the default
        let format: SevenZipCompressionOptions.Format =
            target.pathExtension.lowercased() == "7z" ? .sevenZ : .zip
        let effectiveOptions = options ?? SevenZipCompressionOptions(format: format)

        isSaving = true
        isBusy = true
        progress = 0
        updateStatus(.processing)
        updateStatusText("saving...")
        log.notice("Saving archive", context: [
            "target": target.lastPathComponent,
            "changes": "\(items.count)",
            "new": "\(source == nil)"
        ])

        // Forward 7-Zip's byte progress to the status bar. The callback fires
        // on the writing (GCD) thread — throttle, then hop to the main actor.
        let throttle = ProgressThrottle()
        let onWriteProgress: @Sendable (UInt64, UInt64) -> Bool = { completed, total in
            guard total > 0 else { return true }
            let pct = Int((completed * 100) / total)
            if throttle.shouldEmit(at: Date()) {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self.progress = pct }
                }
            }
            return true
        }

        // the write is a long synchronous C call — keep it off the
        // cooperative pool; bracket any stored security-scoped grant
        let performWrite: @MainActor () async throws -> Void = {
            var accessedFiles: [URL] = []
            for case let .addFile(_, diskPath, _, _) in items {
                if diskPath.startAccessingSecurityScopedResource() {
                    accessedFiles.append(diskPath)
                }
            }
            defer { for f in accessedFiles { f.stopAccessingSecurityScopedResource() } }

            let work: @Sendable () throws -> Void = {
                try SevenZipArchive.writeArchive(
                    source: source,
                    destination: target,
                    items: items,
                    options: effectiveOptions,
                    progress: onWriteProgress
                )
            }
            try await Sandbox.access(url: target) {
                try await runBlocking(work)
            }
        }

        /// The archive may have been opened with a read-only grant (e.g. a
        /// path handed over without a powerbox grant). Then the write fails
        /// with a no-permission error — ask for folder access exactly like
        /// the split-volume loader does, and retry once.
        let isPermissionError: (Error) -> Bool = { error in
            let ns = error as NSError
            if ns.domain == NSCocoaErrorDomain,
               ns.code == NSFileWriteNoPermissionError || ns.code == NSFileReadNoPermissionError {
                return true
            }
            if case SevenZipError.writeFailed(let msg) = error {
                return msg.contains("Cannot create output file") || msg.contains("Cannot open")
            }
            return false
        }

        return Task {
            do {
                do {
                    try await performWrite()
                } catch where isPermissionError(error) {
                    log.notice("Save hit a permission error — asking for folder access", context: ["target": target.lastPathComponent])
                    guard let provider = folderAccessProvider, await provider(target) else {
                        throw error
                    }
                    try await performWrite()
                }

                diff.removeAll()
                self.progress = nil
                log.notice("Archive saved", context: ["target": target.lastPathComponent])

                // reload from disk so entries and indices reflect the file
                open(url: target)
                _ = try? await openTask?.value
                self.isSaving = false
            } catch {
                log.error("Archive save failed", context: [
                    "target": target.lastPathComponent,
                    "error": String(describing: error)
                ])
                self.error = error.localizedDescription
                self.isBusy = false
                self.isSaving = false
                self.progress = nil
                updateStatusText(nil)
                updateStatus(.done)
            }
        }
    }
    
    //
    // MARK: Open
    //
    
    /// Opens the given url.
    /// - Parameter url: url of the archiver to open
    /// The archive's display name. For a split volume, the name the set reassembles
    /// to — the base with the volume suffix replaced by the format's extension
    /// (`split.z02`/`split.zip` → `split.zip`, `x.zip.003` → `x.zip`) — so the title
    /// names the set, not the specific part opened. Purely lexical, no file read;
    /// plain archives keep their file name.
    private func splitSetName(for url: URL) -> String {
        let file = url.lastPathComponent
        for split in catalog.allSplits()
        where file.range(of: split.pattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return file.replacingOccurrences(of: split.pattern, with: ".\(split.format)",
                                             options: [.regularExpression, .caseInsensitive])
        }
        return file
    }

    public func open(url: URL) {
        reset()
        updateStatus(.processing)
        
        self.hasArchive = true
        self.isBusy = true
        self.error = nil
        self.url = url
        self.name = splitSetName(for: url)
        self.ext = url.pathExtension
        log.info("Opening archive", context: ["file": url.lastPathComponent, "ext": url.pathExtension])
        
        openTask = Task {
            do {
                let passwordResolver = makePasswordResolver()
                let archiveLoader = ArchiveLoader(
                    archiveTypeDetector: self.archiveTypeDetector,
                    archiveEngineSelector: self.archiveEngineSelector,
                    passwordResolver: passwordResolver,
                    folderAccessResolver: makeFolderAccessResolver()
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
                    log.error("Archive load reported an error", context: ["file": url.lastPathComponent, "error": loaderResult.error ?? "?"])
                }
                self.root = loaderResult.root
                self.selectedItem = loaderResult.root
                
                self.type = loaderResult.type
                self.compositionType = loaderResult.compositionType
                // Split archive: show the canonical first volume as the window
                // identity, whichever part the user actually opened.
                if let firstVolume = loaderResult.firstVolumeURL {
                    self.url = firstVolume
                }
                if let type,
                    type.engines.contains(where: {$0.capabilities.contains(where: {$0 == "edit"})}) {
                    canBeEdited = true
                }
                
                self.uncompressedSize = loaderResult.uncompressedSize
                
                updateStatusText("building tree...")
                
                try Task.checkCancellation()
                
                if !loaderResult.hasTree {
                    let builderResult = await archiveLoader.buildTree(at: loaderResult.root)
                    self.error = builderResult.error
                    if let treeError = builderResult.error {
                        log.error("Tree build failed", context: ["file": url.lastPathComponent, "error": treeError])
                    }
                }
                self.entries.merge(loaderResult.entries, uniquingKeysWith: { lhs, _ in lhs })
                self.entries[loaderResult.root.id] = root

                loadChildren()
                log.notice("Archive ready to display", context: [
                    "file": url.lastPathComponent,
                    "entries": "\(self.entries.count)",
                    "topLevelItems": "\(self.childItems?.count ?? 0)",
                    "hasTree": "\(loaderResult.hasTree)"
                ])

                updateStatusText(nil)
                
                self.selectedItems = []
                
                self.isBusy = false
                self.isReloadNeeded = true
                self.archiveLoader = nil
                
                try Task.checkCancellation()
            } catch is CancellationError {
                reset()
            } catch ArchiveError.invalidArchive {
                // happens when the loaded archive is an unknown archive
                log.notice("Unsupported or invalid archive", context: ["file": url.lastPathComponent])
                reset()
            } catch {
                log.error("Failed to open archive", context: ["file": url.lastPathComponent, "error": error.localizedDescription])
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
                loadChildren()
            }
        case .archive:
            // TODO: This can never happen as each archive is also of type .file > Remove .archive as a type
            break
        case .virtual:
            self.selectedItem = item
            loadChildren()
            break
        case .directory:
            self.selectedItem = item
            loadChildren()
            break
        case .root:
            self.selectedItem = item
            loadChildren()
            break
        case .unknown:
            log.error("Unhandled ArchiveItem.Type: \(item.name)")
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
        loadChildren()
        
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
            loadChildren()
        } else {
            // Could not detect any archive, just open the file in the system
            // editor — via the app-injected opener (no-op under tests).
            openFileExternally(tempUrl)
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
                    passwordResolver: passwordResolver,
                    folderAccessResolver: makeFolderAccessResolver()
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
                
                loadChildren()
                
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
    
    /// Builds the engine byte-progress callback for a job: throttled,
    /// timestamped-at-emission forwarding to the center, plus cooperative
    /// abort through the cancel flag (stops the C extraction mid-flight).
    private func makeEngineProgress(
        jobId: UUID,
        cancelFlag: ExtractionCancelFlag
    ) -> ArchiveExtractionProgress {
        let center = progressCenter
        let throttle = ProgressThrottle()
        return { completed, total in
            let now = Date()
            if throttle.shouldEmit(at: now) {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        center.reportEngineProgress(jobId, completed: completed, total: total, at: now)
                    }
                }
            }
            return !cancelFlag.isCancelled
        }
    }

    /// Sum of the known uncompressed sizes of the given file items.
    /// ponytail: folders are resolved during extraction, so folder-heavy
    /// selections under-count and fall back to an indeterminate bar (nil).
    private static func plannedBytes(of items: [ArchiveItem]) -> Int64? {
        let known = items
            .filter { $0.type == .file && $0.uncompressedSize > 0 }
            .map { Int64($0.uncompressedSize) }
        guard !known.isEmpty else { return nil }
        return known.reduce(0, +)
    }

    /// Fulfills a drag-out file promise: extracts the item and moves it to
    /// the location the drop target chose. Reported to the progress center
    /// like every other user-visible extraction, so dragging a large file
    /// out to Finder shows the extraction window too.
    /// - Parameters:
    ///   - item: item being dragged out
    ///   - url: full target url provided by the file promise
    public func fulfillDrag(item: ArchiveItem, to url: URL) async throws {
        let tempDirs = ExtractionTempDirectories()
        let jobId = progressCenter.begin(
            archiveName: name ?? self.url?.lastPathComponent ?? "Archive",
            destination: url.deletingLastPathComponent(),
            itemCount: 1,
            totalBytes: Self.plannedBytes(of: [item])
        )

        // own task so the window's cancel button can stop the extraction
        let cancelFlag = ExtractionCancelFlag()
        let work = Task {
            let batchResolver = ArchiveBatchResolver()
            guard let batch = try batchResolver.resolveBatches(for: [item], in: entries, using: archiveEngineSelector).first else {
                throw ArchiveError.extractionFailed("Could not resolve batch")
            }
            let extractor = ArchiveExtractor(
                archiveEngineSelector: archiveEngineSelector,
                passwordResolver: makePasswordResolver(),
                onTempDirectoryCreated: { tempUrl in
                    tempDirs.add(tempUrl)
                }
            )
            let result = try await extractor.extract(
                batch: batch,
                onProgress: makeEngineProgress(jobId: jobId, cancelFlag: cancelFlag)
            )
            tempDirectories.append(result.tempDir)
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: result.url, to: url)
        }
        progressCenter.setOnCancel(jobId) {
            cancelFlag.cancel()
            work.cancel()
        }

        do {
            try await work.value
            progressCenter.finish(jobId, .done)
        } catch is CancellationError {
            // partial temp output of the aborted extraction must not
            // linger — register it for the regular cache cleanup
            tempDirectories.append(contentsOf: tempDirs.all)
            progressCenter.finish(jobId, .cancelled)
            throw CancellationError()
        } catch {
            extractLog.error(error)
            tempDirectories.append(contentsOf: tempDirs.all)
            progressCenter.finish(jobId, .failed(error.localizedDescription))
            throw error
        }
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

        let tempDirs = ExtractionTempDirectories()
        let extractor = ArchiveExtractor(
            archiveEngineSelector: archiveEngineSelector,
            passwordResolver: makePasswordResolver(),
            onTempDirectoryCreated: { url in
                tempDirs.add(url)
            }
        )
        let batchResolver = ArchiveBatchResolver()

        let jobId = progressCenter.begin(
            archiveName: name ?? url?.lastPathComponent ?? "Archive",
            destination: destination,
            itemCount: items.count,
            totalBytes: Self.plannedBytes(of: items)
        )

        let cancelFlag = ExtractionCancelFlag()
        let task = Task {
            do {
                let batches = try batchResolver.resolveBatches(for: items, in: entries, using: archiveEngineSelector)
                let result = try await extractor.extract(
                    batches: batches,
                    to: destination,
                    onProgress: makeEngineProgress(jobId: jobId, cancelFlag: cancelFlag)
                )
                tempDirectories.append(contentsOf: result.tempDirs)
                progressCenter.finish(jobId, .done)
            } catch is CancellationError {
                // partial temp output of the aborted extraction must not
                // linger — register it for the regular cache cleanup
                tempDirectories.append(contentsOf: tempDirs.all)
                progressCenter.finish(jobId, .cancelled)
            } catch {
                extractLog.error(error)
                self.error = error.localizedDescription
                self.isBusy = false
                tempDirectories.append(contentsOf: tempDirs.all)
                progressCenter.finish(jobId, .failed(error.localizedDescription))
            }
            
            updateStatus(.done)
        }
        progressCenter.setOnCancel(jobId) {
            cancelFlag.cancel()
            task.cancel()
        }
    }
    
    public func extract(to destination: URL) {
        isBusy = true
        updateStatus(.processing)

        let jobId = progressCenter.begin(
            archiveName: name ?? url?.lastPathComponent ?? "Archive",
            destination: destination,
            itemCount: entries.values.count(where: { $0.type == .file }),
            totalBytes: (uncompressedSize ?? 0) > 0 ? uncompressedSize : nil
        )

        let cancelFlag = ExtractionCancelFlag()
        let task = Task {
            do {
                guard let root else {
                    throw ArchiveError.extractionFailed("No root item set")
                }
                guard let (archiveTypeId, archiveUrl) = ArchiveSupportUtilities().findHandlerAndUrl(for: root, in: entries) else {
                    throw ArchiveError.extractionFailed("No archive handler found")
                }

                let extractor = ArchiveExtractor(
                    archiveEngineSelector: archiveEngineSelector,
                    passwordResolver: makePasswordResolver()
                )
                try await extractor.extractAll(
                    archiveUrl,
                    archiveTypeId: archiveTypeId,
                    to: destination,
                    onProgress: makeEngineProgress(jobId: jobId, cancelFlag: cancelFlag)
                )
                progressCenter.finish(jobId, .done)
            } catch is CancellationError {
                progressCenter.finish(jobId, .cancelled)
            } catch {
                extractLog.error(error)
                self.error = error.localizedDescription
                progressCenter.finish(jobId, .failed(error.localizedDescription))
            }

            self.isBusy = false
            updateStatus(.done)
        }
        progressCenter.setOnCancel(jobId) {
            cancelFlag.cancel()
            task.cancel()
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
                extractLog.error(error)
                self.error = error.localizedDescription
                self.isBusy = false
            }
            
            updateStatus(.done)
        }
    }
    
    public func changeSelection(selection: IndexSet) {
        log.debug("Selection changed: tableViewSelectionDidChange(_:)")
        
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

