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

private extension ArchiveUpdateItem {
    /// Where an addition goes in the archive; `nil` for a removal or a move.
    var addedPath: String? {
        switch self {
        case .addFile(let path, _, _, _), .addDirectory(let path, _, _, _), .addData(let path, _, _, _): path
        case .remove, .move: nil
        }
    }
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
    /// The engine that actually read this archive. Usually the chosen one, but
    /// not when automatic mode fell back because the chosen engine cannot read
    /// this particular archive — so it is the honest answer to "which engine am
    /// I looking at?", for the UI and for tests.
    @Published private(set) public var activeEngine: ArchiveEngineType?
    
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

    // Live filter over the whole archive. While non-empty, the table shows
    // every entry whose name matches instead of the current folder.
    @Published private(set) public var searchText: String = ""
    
    // UI State
    @Published private(set) public var isBusy: Bool = false
    @Published private(set) public var statusText: String? = nil
    @Published private(set) public var progress: Int? = nil
    @Published private(set) public var error: String? = nil
    /// Why the last `open(url:)` failed, for the window to show.
    ///
    /// Separate from `error`, which extraction also sets — those already report
    /// through the progress window, so alerting on them too would say everything
    /// twice. A failed open has no other surface at all: it ends in `reset()`,
    /// so the window goes back to its empty state and the user sees nothing.
    @Published private(set) public var openError: String? = nil
    /// Why the last save failed or was refused, for the window to show. As with
    /// `openError`, nothing else would: the status bar just stops, and the
    /// window looks saved.
    @Published private(set) public var saveError: String? = nil
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
    /// The engine that read this window's archives, by format — the archive and
    /// any opened inside it. Every later lookup gets it, whatever Settings say
    /// by then: entries are numbered by the engine that listed them, and 7-Zip
    /// takes XAD's numbers for other entries. It is also where the loader's
    /// fallback stays, when the configured engine could not open the archive.
    /// Cleared on reset with the rest of the archive state.
    private var pinnedEngines: [String: ArchiveEngineType] = [:]

    /// The selector everything downstream should use.
    private var effectiveEngineSelector: ArchiveEngineSelectorProtocol {
        pinnedEngines.isEmpty
            ? archiveEngineSelector
            : AutomaticEngineSelector(base: archiveEngineSelector, pinned: pinnedEngines)
    }
    private let archiveTypeDetector: ArchiveTypeDetector
    
    private var tempDirectories: [URL] = []
    
    public var passwordProvider: ArchivePasswordUserProvider?
    public var folderAccessProvider: ArchiveFolderAccessUserProvider?
    /// Hands a plain (non-archive) file to the system after extraction. The app
    /// wires this to `NSWorkspace.shared.open`; the default is a no-op so Core
    /// carries no AppKit dependency and unit tests never launch an external app.
    public var openFileExternally: (URL) -> Void = { _ in }
    /// Brings forward the window that already has the archive at this url open,
    /// and says whether there was one. The app wires this to its window manager;
    /// the default finds none, so Core and the unit tests open in place.
    public var focusWindowHolding: (URL) -> Bool = { _ in false }
    /// Where user-triggered extractions report their progress. Defaults to
    /// the app-wide center that feeds the extraction progress window;
    /// tests inject their own instance.
    public var progressCenter: ExtractionProgressCenter = .shared
    /// Passwords the user gave, by the file they were given for. One window can
    /// hold more than one archive: an archive inside the archive opens in the
    /// same tree, extracted to a temp file, and each can have its own password.
    /// Keyed by file, a password only ever goes to the file it was typed for.
    /// Emptied on every open and when the window closes.
    private var passwords: [URL: String] = [:]
    /// Bumped by every `open(url:)`. A load whose generation is stale has been
    /// superseded and must stop touching the state: two overlapping opens both
    /// wrote to it, so which archive the window ended up showing depended on
    /// which load happened to finish last.
    private var openGeneration = 0
    /// The archive's file as this window opened it. A pending removal names its
    /// entry by position in that file, so a save must not go ahead once anything
    /// else has written to it.
    private var openedFile: FileStamp?

    public private(set) var openTask: Task<Void, any Error>?
    /// The add started last. What it adds is read off the main actor, so it is
    /// there once this ends.
    public private(set) var addTask: Task<Bool, Never>?
    /// Adds started and not yet done. Nothing is saved before what they are
    /// reading is in the archive.
    private var pendingAdds = 0
    /// Stops the add that is reading right now.
    private var addCancel: ExtractionCancelFlag?
    /// Bumped by a cancel, so the adds waiting their turn go with the one that
    /// was reading: several files dropped together are one add each.
    private var addCancellations = 0
    /// Bumped whenever the archive in the window is replaced or closed, so an
    /// add that was reading for the one before can tell.
    private var contentGeneration = 0
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

            // A repeat request means the password we last handed out did not
            // work, so the cached one is stale — drop it and ask again.
            // Serving the cache unconditionally used to spin the engine's retry
            // loop at full speed against the same wrong password, with no
            // prompt and no error: the "stuck at 0%, 100% CPU" report.
            if request.attempt > 1 {
                self.passwords.removeValue(forKey: request.url)
            } else if let password = passwords[request.url] {
                return password
            }

            // if not cached, ask the user to provide the password
            passwordLog.info("Password requested", context: [
                "archive": request.url.lastPathComponent,
                "attempt": String(request.attempt)
            ])
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

    /// How a `passwordCancelled` should be reported.
    ///
    /// Dismissing the prompt is the user's own choice, so the job just ends as
    /// cancelled. Having no prompt at all is different: Finder's "Extract Here"
    /// and QuickLook build an ArchiveState with no `passwordProvider`, so an
    /// encrypted archive used to fail there with nothing shown and nothing
    /// extracted. That needs to be a failure with a message that says what to do.
    private func passwordCancelledOutcome() -> ExtractionJob.State {
        guard passwordProvider == nil else { return .cancelled }
        let archiveName = name ?? String(localized: "The archive", bundle: .module, comment: "Fallback archive name in a password-required error")
        return .failed(String(localized: "\(archiveName) is password protected. Open it in MacPacker to enter the password.", bundle: .module, comment: "Error shown when an encrypted archive cannot request a password"))
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
        // whatever is still being read for an add was meant for what goes now
        contentGeneration += 1
        addCancel?.cancel()
        addCancel = nil

        self.hasArchive = false
        self.canBeEdited = false
        // A failed open sets its reason after this, so its alert still shows.
        self.openError = nil
        self.saveError = nil

        self.url = nil
        self.openedFile = nil
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
        self.searchText = ""

        self.childItems = nil
        
        self.archiveLoader = nil
        
        self.passwords = [:]
        self.pinnedEngines = [:]
        self.activeEngine = nil
        
        updateStatus(.idle)
        
        CacheCleaner().clean(tempDirectories: tempDirectories)
    }
    
    public func clean() {
        reset()
    }

    /// Dismisses the failed-open message once the user has seen it.
    public func clearOpenError() {
        openError = nil
    }

    /// Dismisses the failed-save message once the user has seen it.
    public func clearSaveError() {
        saveError = nil
    }
    
    /// Cancels the current operation which can be either loading the archive or extracting
    /// anything from the archive
    public func cancelCurrentOperation() {
        // Files being read for an add: stop reading, and leave the archive as
        // it is. Below is for a load, and ends in a reset.
        if let addCancel {
            addCancellations += 1
            addCancel.cancel()
            return
        }

        openTask?.cancel()

        // Capture what is being cancelled before suspending. Awaiting the loader
        // is a suspension point, and a new open can start during it — that open
        // owns the state and has its own loader by the time this resumes, so
        // clearing and resetting blindly would wipe an archive the user just
        // opened successfully.
        let cancelledLoader = archiveLoader
        let generation = openGeneration

        Task {
            await cancelledLoader?.cancel()

            guard generation == openGeneration,
                  archiveLoader === cancelledLoader else { return }

            archiveLoader = nil
            reset()
        }
    }
    
    //
    // MARK: Search
    //

    public var isSearching: Bool { !searchText.isEmpty }

    /// Whether there is an enclosing folder to go up to.
    public var canGoUp: Bool {
        guard let selectedItem else { return false }
        return selectedItem.type != .root
    }

    /// Whether the table shows the ".." row at the top: off unless the user
    /// switches it on, and never in search results (they come from all levels
    /// at once, so there is no single parent to go up to). The toolbar's back
    /// button and ⌘↑ go up either way.
    public var showsParentRow: Bool {
        guard !isSearching, canGoUp else { return false }
        return UserDefaults.standard.bool(forKey: Keys.showParentRow)
    }

    /// Updates the live search. Every change re-filters the entries; clearing
    /// the text returns the table to the folder that was being browsed.
    public func search(_ text: String) {
        guard text != searchText else { return }
        searchText = text
        selectedItems = []
        isReloadNeeded = true
        loadChildren()
    }

    /// Navigation leaves search mode — going into a folder (or up) shows that
    /// folder, not the stale result list.
    private func clearSearch() {
        guard isSearching else { return }
        searchText = ""
    }

    /// All entries (any level) whose name contains the search text. Sorted
    /// like the browse view; without a stored order, by name — dictionary
    /// order would make the results jump around on every keystroke.
    private func searchResults() -> [ArchiveItem] {
        let matches = entries.values.filter {
            $0.type != .root && $0.name.localizedCaseInsensitiveContains(searchText)
        }
        guard UserDefaults.standard.string(forKey: Keys.defaultOrderColumn) != nil else {
            return matches.sorted { a, b in
                if a.isFolder != b.isFolder { return a.isFolder }
                let cmp = a.name.localizedStandardCompare(b.name)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                return isBeforeByPath(a, b)
            }
        }
        return sortedForDisplay(matches)
    }

    /// Settles two entries the chosen column cannot separate. Ties are the rule,
    /// not the exception — same name in two folders, same size, same timestamp —
    /// and `sorted(by:)` is free to order equal elements any way it likes, so
    /// without this the rows reshuffle as the search set narrows.
    private func isBeforeByPath(_ a: ArchiveItem, _ b: ArchiveItem) -> Bool {
        let cmp = (a.virtualPath ?? a.name).localizedStandardCompare(b.virtualPath ?? b.name)
        if cmp != .orderedSame { return cmp == .orderedAscending }
        return a.id.uuidString < b.id.uuidString
    }

    public func loadChildren() {
        guard let selectedItem else { return }

        if isSearching {
            childItems = searchResults()
            return
        }

        guard UserDefaults.standard.string(forKey: Keys.defaultOrderColumn) != nil else {
            childItems = selectedItem.children?.compactMap { entries[$0] }
            return
        }

        if let children = selectedItem.children?.compactMap({ entries[$0] }) {
            childItems = sortedForDisplay(children)
        }
    }

    private func sortedForDisplay(_ items: [ArchiveItem]) -> [ArchiveItem] {
        let defaultOrderColumn = UserDefaults.standard.string(forKey: Keys.defaultOrderColumn)
        let defaultOrderColumnAscending = UserDefaults.standard.bool(forKey: Keys.defaultOrderColumnAscending)

        return items.sorted { a, b in
                switch defaultOrderColumn {
                case ArchiveSortOrder.name.rawValue:
                    if a.isFolder != b.isFolder {
                        return a.isFolder
                    }

                    let cmp = a.name.localizedStandardCompare(b.name)
                    if cmp != .orderedSame {
                        return defaultOrderColumnAscending ? cmp == .orderedAscending : cmp == .orderedDescending
                    }

                case ArchiveSortOrder.modificationDate.rawValue:
                    let lhs = a.modificationDate ?? .distantPast
                    let rhs = b.modificationDate ?? .distantPast

                    if lhs != rhs {
                        return defaultOrderColumnAscending ? lhs < rhs : lhs > rhs
                    }

                case ArchiveSortOrder.uncompressedSize.rawValue:
                    if a.uncompressedSize != b.uncompressedSize {
                        return defaultOrderColumnAscending
                        ? a.uncompressedSize < b.uncompressedSize
                        : a.uncompressedSize > b.uncompressedSize
                    }

                case ArchiveSortOrder.compressedSize.rawValue:
                    if a.compressedSize != b.compressedSize {
                        return defaultOrderColumnAscending
                        ? a.compressedSize < b.compressedSize
                        : a.compressedSize > b.compressedSize
                    }

                case ArchiveSortOrder.posixPermissions.rawValue:
                    let lhs = a.posixPermissions ?? 0
                    let rhs = b.posixPermissions ?? 0

                    if lhs != rhs {
                        return defaultOrderColumnAscending ? lhs < rhs : lhs > rhs
                    }

                default:
                    break
                }

                // the column above left them equal — settle it the same way every time
                return isBeforeByPath(a, b)
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
                case .processing(let progress, let activity):
                    switch activity {
                    case .buildingTree:
                        updateStatusText(String(localized: "building tree...", bundle: .module, comment: "Archive operation status"))
                    case .loadingEngine(_),
                         .engineLoaded(_, _),
                         .temporaryDirectoryCreated(_),
                         .entriesFound(_),
                         .entryExtracted(_),
                         .splitFirstVolume(_),
                         .archiveURLLost(typeID: _),
                         .invalidArchiveType(typeID: _):
                        updateStatusText(String(localized: "loading...", bundle: .module, comment: "Archive operation status"))
                    }
                    if let progress {
                        self.progress = Int(progress)
                    }
                case .done:
                    updateStatusText(String(localized: "done", bundle: .module, comment: "Archive operation status"))
                    self.progress = nil
                    log.debug("status: done")
                case .error(let error):
                    updateStatusText(String(localized: "error: \(error.localizedDescription)", bundle: .module, comment: "Archive operation status that includes an error description"))
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

    /// Extension-only check, for saying up front what a *drag* would do. The file
    /// isn't readable while it hovers — the sandbox grants access on the drop — so
    /// its content can't be sniffed and the name is all there is to go on.
    public func looksLikeArchive(url: URL) -> Bool {
        return archiveTypeDetector.detectByExtension(for: url, considerComposition: true) != nil
    }
    
    //
    // MARK: Create / Edit
    //
    
    /// `name` is what the window and the breadcrumb show until the archive is
    /// saved. Core has no string catalog, so the app passes its localized one.
    public func create(named name: String = "New Archive") {
        reset()

        self.canBeEdited = true
        self.hasArchive = true
        // self.url = nil
        self.name = name
        self.type = self.catalog.getType(for: "zip")
        self.ext = ".zip"
        
        // Named like the archive, not "<root>": the breadcrumb shows this item,
        // and a placeholder there is the first thing a new archive shows.
        self.root = ArchiveItem(name: self.name ?? "", virtualPath: "/", type: .root)

        self.isReloadNeeded = true
        
        self.selectedItem = root
        loadChildren()
    }
    
    /// Adds files and folders from disk where the window is; a folder goes in
    /// with everything it holds.
    ///
    /// They are read off the main actor, by `FileScanner`, so what was added
    /// is there once the returned task ends. An add started meanwhile waits its
    /// turn, and what it adds comes after.
    ///
    /// - Returns: the add. Its value is whether all of `urls` was added: a
    ///   folder that can't be read is left out, with the reason in `error`, and
    ///   so is one inside it.
    @discardableResult
    public func add(urls: [URL]) -> Task<Bool, Never> {
        add(urls: urls, cancel: ExtractionCancelFlag())
    }

    @discardableResult
    public func add(url: URL) -> Task<Bool, Never> {
        add(urls: [url])
    }

    private func add(urls: [URL], cancel: ExtractionCancelFlag) -> Task<Bool, Never> {
        // Where the window is now is where it goes, wherever the window is by
        // the time it has been read.
        let target = selectedItem
        let generation = contentGeneration
        let cancellations = addCancellations
        let previous = addTask
        pendingAdds += 1
        let task = Task {
            _ = await previous?.value
            var added = false
            // unless it was cancelled while it waited its turn
            if cancellations == addCancellations {
                added = await scanAndAdd(urls, under: target, of: generation, cancel: cancel)
            }
            pendingAdds -= 1
            return added
        }
        addTask = task
        return task
    }

    /// - Parameters:
    ///   - target: the folder shown when the add was asked for
    ///   - generation: the archive the window held then
    private func scanAndAdd(
        _ urls: [URL],
        under target: ArchiveItem?,
        of generation: Int,
        cancel: ExtractionCancelFlag
    ) async -> Bool {
        guard !isSaving else {
            log.notice("Ignoring add — a save is in progress", context: ["files": "\(urls.count)"])
            return false
        }
        // `create`, `open` or closing the window replaced the archive this was
        // for: whatever the window shows now is not where it goes.
        guard let target, generation == contentGeneration else { return false }
        // A save writes only this archive. Added inside one opened within it,
        // the file would land in this one, in a folder named like that archive.
        guard !isWithinOpenedArchive(target) else {
            log.notice("Ignoring add — inside an archive opened within this one", context: ["files": "\(urls.count)"])
            return false
        }
        let base = (target.virtualPath?.isEmpty == false && target.virtualPath != "/")
            ? target.virtualPath! + "/" : ""

        isBusy = true
        addCancel = cancel
        updateStatus(.processing)
        updateStatusText(String(localized: "loading...", bundle: .module, comment: "Archive operation status"))
        let scan = try? await FileScanner().scan(urls, under: base, cancel: cancel)

        // replaced while it was read: the same, and the busy state is no longer
        // this add's to clear
        guard generation == contentGeneration else { return false }
        isBusy = false
        addCancel = nil
        updateStatusText(nil)
        updateStatus(.done)
        // cancelled, or the folder it was going into was removed meanwhile
        guard let scan, target === root || entries[target.id] != nil else { return false }

        put(scan, under: target)
        if let unreadable = scan.unreadable {
            self.error = unreadable
        }
        self.isReloadNeeded = true
        loadChildren()
        return scan.unreadable == nil
    }

    /// Puts what a scan read under `target`, in one change to `entries` and one
    /// to `diff`. Both are published: changed entry by entry, every change
    /// copies the whole collection, and with 20,000 files that alone took most
    /// of 11 seconds (#278).
    ///
    /// A name the archive already holds is replaced, or the file the user meant
    /// to replace would still be in there next to its replacement. Except a
    /// folder over a folder: that one is merged into, so only the files that
    /// collide inside it are replaced and the rest of what it holds stays.
    private func put(_ scan: FileScan, under target: ArchiveItem) {
        var entries = self.entries
        var replaced = Removal()
        var additions: [ArchiveUpdateItem] = []
        additions.reserveCapacity(scan.entries.count)
        // What each scanned entry ended up as: itself, or the folder already
        // there that it was merged into.
        var placed: [ArchiveItem] = []
        placed.reserveCapacity(scan.entries.count)
        // The names taken in the folders that were there before this add. Only
        // there can anything collide: below a folder the add brought itself,
        // the disk has kept the names apart already.
        var taken: [UUID: [String: ArchiveItem]] = [:]

        for entry in scan.entries {
            let item = entry.item
            let parent = entry.parent.map { placed[$0] } ?? target
            let broughtWithItsFolder = entry.parent.map { placed[$0] === scan.entries[$0].item } ?? false
            if !broughtWithItsFolder {
                // taken out and put back, so that it is changed in place
                var names = taken.removeValue(forKey: parent.id) ?? Dictionary(
                    (parent.children ?? []).compactMap { entries[$0] }.map { ($0.name, $0) },
                    uniquingKeysWith: { first, _ in first })
                defer { taken[parent.id] = names }

                let existing = names[item.name]
                if let existing, existing.isFolder, item.isFolder {
                    placed.append(existing)
                    continue
                }
                if let existing {
                    var gone = Removal()
                    take(existing, outOf: &entries, into: &gone)
                    parent.removeChild(existing.id)
                    // Brought by this very add, by an earlier one of its files
                    // with the same name: not in `diff` yet for `drop` to find.
                    if self.entries[existing.id] == nil {
                        additions.removeAll { $0.addedPath.map(gone.pendingPaths.contains) ?? false }
                    }
                    replaced.formUnion(gone)
                }
                names[item.name] = item
                item.parent = parent.id
                parent.addChild(item.id)
            }
            entries[item.id] = item
            additions.append(entry.update)
            placed.append(item)
        }

        var diff = self.diff
        drop(replaced, from: &diff)
        diff.append(contentsOf: additions)
        self.entries = entries
        self.diff = diff
        if !replaced.isEmpty {
            // a replaced item must not stay selected — it is gone from `entries`
            selectedItems = selectedItems.filter { entries[$0.id] != nil }
        }
    }

    /// How a save ended.
    private enum SaveOutcome {
        case written
        case failed
        case cancelled
    }

    /// Makes this fresh state a new archive at `destination` holding `items`,
    /// written in one go: Quick Compress and the Finder's compress entries.
    ///
    /// Writes nothing once an item can't be read in full. Left out, it would
    /// leave an archive short of what was asked for that still reports done —
    /// for a single folder, an empty one (#278).
    ///
    /// - Parameter showingProgress: for a compress with no window of its own to
    ///   show its progress in — the Finder's entries. It is reported to the
    ///   progress center like an extraction: the progress window comes up once
    ///   it takes long enough, can cancel it, and stays up to say why it failed;
    ///   and the app asks before it quits in the middle of it.
    /// - Returns: whether the archive was written. When it was not, `error` says
    ///   why — unless it was cancelled.
    @discardableResult
    public func compress(
        _ items: [URL],
        to destination: URL,
        options: CompressionOptions? = nil,
        showingProgress: Bool = false
    ) async -> Bool {
        create()

        let cancel = ExtractionCancelFlag()
        // Before anything is read: reading a large folder is part of the wait.
        let job = showingProgress ? progressCenter.begin(
            kind: .compression,
            archiveName: destination.lastPathComponent,
            destination: destination.deletingLastPathComponent(),
            itemCount: items.count,
            totalBytes: nil
        ) : nil
        if let job {
            progressCenter.setOnCancel(job) { cancel.cancel() }
        }

        var outcome = SaveOutcome.failed
        if await add(urls: items, cancel: cancel).value {
            outcome = await startSave(to: destination, options: options, job: job, cancel: cancel)?.value ?? .failed
        } else if cancel.isCancelled {
            outcome = .cancelled
        }

        if let job {
            switch outcome {
            case .written: progressCenter.finish(job, .done)
            case .cancelled: progressCenter.finish(job, .cancelled)
            case .failed: progressCenter.finish(job, .failed(error ?? ""))
            }
        }
        return outcome == .written
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
        guard canRemove(items) else {
            log.notice("Ignoring delete — nothing this archive can remove", context: ["items": "\(items.count)"])
            return
        }

        // One change to `entries` and one to `diff`, as for an add: see `put`.
        var entries = self.entries
        var removal = Removal()
        for item in items {
            take(item, outOf: &entries, into: &removal)
            if let parentId = item.parent {
                entries[parentId]?.removeChild(item.id)
            }
        }
        var diff = self.diff
        drop(removal, from: &diff)
        self.entries = entries
        self.diff = diff

        log.notice("Marked items for removal", context: [
            "items": "\(items.count)",
            "archiveEntries": "\(removal.indices.count)",
            "pendingAdds": "\(removal.pendingPaths.count)"
        ])

        selectedItems = []
        isReloadNeeded = true
        loadChildren()
    }

    /// What taking items out of the tree comes to in the diff.
    private struct Removal {
        /// Entries the archive on disk has: a save removes them.
        var indices: Set<UInt32> = []
        /// Additions not saved yet: dropped from the diff again.
        var pendingPaths: Set<String> = []

        var isEmpty: Bool { indices.isEmpty && pendingPaths.isEmpty }

        mutating func formUnion(_ other: Removal) {
            indices.formUnion(other.indices)
            pendingPaths.formUnion(other.pendingPaths)
        }
    }

    /// Depth-first: takes `item` and all of its descendants out of `entries`,
    /// and notes what that comes to in the diff. An archive opened within this
    /// one goes as the entry it is: what it holds leaves the tree with it, but
    /// belongs to that archive, numbered as that one's entries.
    private func take(
        _ item: ArchiveItem,
        outOf entries: inout [UUID: ArchiveItem],
        into removal: inout Removal,
        inThisArchive: Bool = true
    ) {
        for childId in item.children ?? [] {
            if let child = entries[childId] {
                take(child, outOf: &entries, into: &removal,
                     inThisArchive: inThisArchive && item.archiveTypeId == nil)
            }
        }
        if inThisArchive {
            if let index = item.index {
                removal.indices.insert(index)
            } else if let path = item.virtualPath, path != "/" {
                removal.pendingPaths.insert(path)
            }
        }
        entries.removeValue(forKey: item.id)
    }

    /// Records in `diff` that what `removal` names is gone.
    private func drop(_ removal: Removal, from diff: inout [ArchiveUpdateItem]) {
        // pending (unsaved) additions are simply dropped from the diff
        if !removal.pendingPaths.isEmpty {
            diff.removeAll { $0.addedPath.map(removal.pendingPaths.contains) ?? false }
        }
        // entries that exist in the archive on disk are removed on save
        diff.append(contentsOf: removal.indices.sorted().map { .remove(sourceIndex: $0) })
    }

    /// Whether `item` is an archive opened within this one, or inside one: what
    /// such an archive holds is that archive's, and a save writes only this one.
    private func isWithinOpenedArchive(_ item: ArchiveItem) -> Bool {
        var current: ArchiveItem? = item
        while let node = current, node.type != .root {
            if node.archiveTypeId != nil { return true }
            current = node.parent.flatMap { entries[$0] }
        }
        return false
    }

    /// Opens a dropped file in this window: a supported archive is opened directly,
    /// unless another window has it open already — that one comes forward instead;
    /// anything else becomes the first entry of a new archive. `open`/`create` reset
    /// the state, so this replaces whatever is currently loaded.
    public func openDropped(url: URL) {
        if isSupportedArchive(url: url) {
            guard !focusWindowHolding(url) else { return }
            open(url: url)
        } else {
            create()
            add(url: url)
        }
    }

    /// Whether there are unsaved changes (pending additions/removals).
    public var hasPendingChanges: Bool { !diff.isEmpty }

    /// Whether `items` can be removed: none of them is inside an archive opened
    /// within this one. The row of such an archive is this archive's own entry,
    /// and can go.
    public func canRemove(_ items: [ArchiveItem]) -> Bool {
        canBeEdited && !isSaving && !items.isEmpty
            && !items.contains { item in item.parent.flatMap { entries[$0] }.map(isWithinOpenedArchive) ?? false }
    }

    /// Whether files can be added where the window is: into this archive, not
    /// into one opened within it.
    public var canAddHere: Bool {
        canBeEdited && !isSaving && selectedItem.map { !isWithinOpenedArchive($0) } == true
    }

    /// Saves the pending changes.
    ///
    /// - For an archive loaded from disk, the changes are applied in place.
    ///   A `destination` makes it a Save As: the archive is written again with
    ///   `options`, onto its own file too.
    /// - For a new archive (never saved), `destination` is required — that's
    ///   where the archive is created.
    ///
    /// After a successful write the archive is reloaded from disk so the
    /// shown entries (and their source indices) match the file again. The
    /// write itself is `ArchiveSaver`'s; this keeps the window's state.
    @discardableResult
    public func save(
        to destination: URL? = nil,
        options: CompressionOptions? = nil
    ) -> Task<Void, Never>? {
        guard let saving = startSave(to: destination, options: options, job: nil, cancel: nil) else { return nil }
        return Task { _ = await saving.value }
    }

    /// - Parameters:
    ///   - job: the progress center's job the write reports its bytes to, if it has one
    ///   - cancel: set to stop the write; what it had written by then is removed
    private func startSave(
        to destination: URL?,
        options: CompressionOptions?,
        job: UUID?,
        cancel: ExtractionCancelFlag?
    ) -> Task<SaveOutcome, Never>? {
        guard !isSaving else {
            log.notice("Ignoring save — a save is already in progress")
            return nil
        }
        // What is still being read is not in `diff` yet: saved now, the archive
        // would be written without it.
        guard pendingAdds == 0 else {
            log.notice("Ignoring save — files are still being added")
            return nil
        }
        guard let target = destination ?? url else { return nil }
        // Save with nothing pending is a no-op. A Save As is not, even of a clean
        // archive onto its own file: its options have to reach every entry.
        guard !diff.isEmpty || destination != nil else { return nil }
        // format follows the target extension; zip is the default
        let format: CompressionOptions.Format =
            target.pathExtension.lowercased() == "7z" ? .sevenZ : .zip
        let saver = ArchiveSaver(
            source: url,
            // From the file's name, by the catalog's split patterns — not by
            // comparing it with `name`, which follows an archive opened inside
            // this one.
            splitArchiveName: url.flatMap { url in
                let setName = splitSetName(for: url)
                return setName == url.lastPathComponent ? nil : setName
            },
            sourceAsOpened: openedFile,
            target: target,
            items: diff,
            options: options ?? CompressionOptions(format: format),
            isSaveAs: destination != nil,
            sourcePassword: url.flatMap { passwords[$0] },
            passwordResolver: makePasswordResolver(),
            folderAccessProvider: folderAccessProvider,
            onProgress: { [weak self, progressCenter] completed, total, date in
                self?.progress = Int((completed * 100) / total)
                if let job {
                    progressCenter.reportEngineProgress(
                        job, completed: Int64(completed), total: Int64(total), at: date)
                }
            },
            cancel: cancel)

        isSaving = true
        isBusy = true
        progress = 0
        updateStatus(.processing)
        updateStatusText(String(localized: "saving...", bundle: .module, comment: "Archive operation status"))
        log.notice("Saving archive", context: [
            "target": target.lastPathComponent,
            "changes": "\(diff.count)",
            "new": "\(url == nil)"
        ])

        return Task {
            do {
                let saved = try await saver.save()
                diff.removeAll()
                self.progress = nil
                log.notice("Archive saved", context: ["target": target.lastPathComponent])

                // reload from disk so entries and indices reflect the file
                let engines = pinnedEngines
                open(url: saved.url)
                // Known already — reopening must not ask again. Set after open(),
                // which starts by forgetting every password, and before the first
                // await, so the load has not asked yet.
                if let password = saved.password {
                    passwords[saved.url] = password
                }
                // Likewise the engine: it is still the archive the window opened,
                // whatever Settings have said since.
                pinnedEngines = engines
                _ = try? await openTask?.value
                self.isSaving = false
                return .written
            } catch SevenZipError.cancelled {
                // Stopped on request, and nothing half-written is left behind:
                // not a failure, and what was pending still is.
                log.notice("Archive save cancelled", context: ["target": target.lastPathComponent])
                self.isBusy = false
                self.isSaving = false
                self.progress = nil
                updateStatusText(nil)
                updateStatus(.done)
                return .cancelled
            } catch {
                log.error("Archive save failed", context: [
                    "target": target.lastPathComponent,
                    "error": String(describing: error)
                ])
                self.error = error.localizedDescription
                self.saveError = error.localizedDescription
                self.isBusy = false
                self.isSaving = false
                self.progress = nil
                updateStatusText(nil)
                updateStatus(.done)
                return .failed
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
            // the format's extension, not its catalog id: a 7z set is "x.7z", not "x.7zip"
            let ext = catalog.getType(for: split.format)?.extensions.first ?? split.format
            return file.replacingOccurrences(of: split.pattern, with: ".\(ext)",
                                             options: [.regularExpression, .caseInsensitive])
        }
        return file
    }

    public func open(url: URL) {
        // A second open supersedes the first. Without cancelling, the earlier
        // task keeps running against the same state.
        openTask?.cancel()
        openGeneration += 1
        let generation = openGeneration

        reset()
        updateStatus(.processing)
        
        self.hasArchive = true
        self.isBusy = true
        self.error = nil
        self.url = url
        // before the load reads it, so a write during the load counts too
        self.openedFile = FileStamp(url)
        self.name = splitSetName(for: url)
        self.ext = url.pathExtension
        log.info("Opening archive", context: ["file": url.lastPathComponent, "ext": url.pathExtension])
        
        openTask = Task {
            do {
                let passwordResolver = makePasswordResolver()
                let archiveLoader = ArchiveLoader(
                    archiveTypeDetector: self.archiveTypeDetector,
                    archiveEngineSelector: self.effectiveEngineSelector,
                    passwordResolver: passwordResolver,
                    folderAccessResolver: makeFolderAccessResolver()
                )
                self.archiveLoader = archiveLoader
                
                let stream = await archiveLoader.statusStream()
                let statusTask = receiveStatusUpdates(from: stream)
                defer { statusTask.cancel() }
                
                updateStatusText(String(localized: "loading...", bundle: .module, comment: "Archive operation status"))
                let loaderResult = try await archiveLoader.loadEntries(url: url)
                // why does root have itself as child here?
                if let tempDirectory = loaderResult.tempDirectory {
                    tempDirectories.append(tempDirectory)
                }
                
                try Task.checkCancellation()
                guard generation == self.openGeneration else { return }

                if loaderResult.error != nil {
                    updateStatusText(String(localized: "failed to load", bundle: .module, comment: "Archive operation status"))
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
                // Changed only by an engine that writes the format, since a
                // change names entries by the numbers of the engine that listed
                // them. XAD only reads, and 7-Zip's writer would take its numbers
                // for other entries.
                if let type, let used = loaderResult.engineType,
                   type.engines.contains(where: { $0.id == used.configId && $0.canEdit }) {
                    canBeEdited = true
                }
                
                self.uncompressedSize = loaderResult.uncompressedSize
                self.isEncrypted = loaderResult.isEncrypted
                // The archive stays with the engine that read it (see
                // `pinnedEngines`). That may be a fallback, when the configured
                // engine cannot read this archive: the first extraction would
                // otherwise resolve the failing engine all over again.
                self.activeEngine = loaderResult.engineType
                if let used = loaderResult.engineType {
                    pinnedEngines[loaderResult.type.id] = used
                    if used != archiveEngineSelector.engineType(for: loaderResult.type.id) {
                        log.notice("Engine pinned for this archive", context: [
                            "file": url.lastPathComponent,
                            "type": loaderResult.type.id,
                            "engine": used.configId
                        ])
                    }
                }

                updateStatusText(String(localized: "building tree...", bundle: .module, comment: "Archive operation status"))
                
                try Task.checkCancellation()
                
                // buildTree synthesizes the directories the archive has no entry
                // for, so its result carries the entries — loaderResult.entries
                // is a snapshot from before and misses them.
                var loadedEntries = loaderResult.entries
                if !loaderResult.hasTree {
                    let builderResult = await archiveLoader.buildTree(at: loaderResult.root)
                    // keep a load error — a clean tree build does not undo it
                    self.error = builderResult.error ?? self.error
                    loadedEntries = builderResult.entries
                    if let treeError = builderResult.error {
                        log.error("Tree build failed", context: ["file": url.lastPathComponent, "error": treeError])
                    }
                }
                self.entries.merge(loadedEntries, uniquingKeysWith: { lhs, _ in lhs })
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
                // Cancelled because a newer open replaced this one: that open now
                // owns the state, so leave it alone.
                guard generation == self.openGeneration else { return }
                reset()
            } catch ArchiveError.invalidArchive(let message) {
                // Half a dozen different failures land here — undetectable type,
                // no engine for the type, an engine that can't read this variant,
                // declined folder access. Logging just "unsupported" made them
                // indistinguishable in a bug report, so carry the reason.
                log.notice("Unsupported or invalid archive", context: [
                    "file": url.lastPathComponent,
                    "reason": message
                ])
                guard generation == self.openGeneration else { return }
                reset()
                self.error = message
                self.openError = message
            } catch {
                log.error("Failed to open archive", context: ["file": url.lastPathComponent, "error": error.localizedDescription])
                guard generation == self.openGeneration else { return }
                reset()
                self.error = error.localizedDescription
                self.openError = error.localizedDescription
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
                updateStatusText(String(localized: "extracting...", bundle: .module, comment: "Archive operation status"))
                
                try await openFile(item)
            } else {
                // Do nothing here. It is an archive. It is extracted already.
                // We have updated the hierarchy already. Just select the item
                clearSearch()
                self.selectedItem = item
                loadChildren()
            }
        case .archive:
            // TODO: This can never happen as each archive is also of type .file > Remove .archive as a type
            break
        case .virtual:
            clearSearch()
            self.selectedItem = item
            loadChildren()
            break
        case .directory:
            clearSearch()
            self.selectedItem = item
            loadChildren()
            break
        case .root:
            clearSearch()
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

        clearSearch()

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
            archiveEngineSelector: self.effectiveEngineSelector,
            passwordResolver: passwordResolver
        )
        let batchResolver = ArchiveBatchResolver()
        guard let batch = try batchResolver.resolveBatches(for: [item], in: entries, using: self.effectiveEngineSelector).first else {
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
           let engine = effectiveEngineSelector.engine(for: detectionResult.type.id) {
            
            // set the services required for this nested archive
            clearSearch()
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
                    archiveEngineSelector: self.effectiveEngineSelector,
                    passwordResolver: passwordResolver,
                    folderAccessResolver: makeFolderAccessResolver()
                )
                
                let stream = await archiveLoader.statusStream()
                let statusTask = receiveStatusUpdates(from: stream)
                defer { statusTask.cancel() }
                
                updateStatusText(String(localized: "loading...", bundle: .module, comment: "Archive operation status"))
                let loaderResult = try await archiveLoader.loadEntries(url: url)
                // Stays with the engine that read it, like the archive around it.
                // One of that archive's format keeps its pin: the pin is per
                // format, and moving it would hand the outer archive's entries to
                // an engine that numbers them otherwise.
                if let used = loaderResult.engineType, pinnedEngines[loaderResult.type.id] == nil {
                    pinnedEngines[loaderResult.type.id] = used
                }
                
                if let tempDirectory = loaderResult.tempDirectory {
                    tempDirectories.append(tempDirectory)
                }
                
                if loaderResult.error != nil {
                    updateStatusText(String(localized: "failed to load", bundle: .module, comment: "Archive operation status"))
                    self.error = loaderResult.error
                }
                self.selectedItem = archiveItem
                
                updateStatusText(String(localized: "building tree...", bundle: .module, comment: "Archive operation status"))
                
                var loadedEntries = loaderResult.entries
                if !loaderResult.hasTree {
                    let builderResult = await archiveLoader.buildTree(at: archiveItem)
                    // keep a load error — a clean tree build does not undo it
                    self.error = builderResult.error ?? self.error
                    loadedEntries = builderResult.entries
                }
                self.entries.merge(loadedEntries) { (current, _) in current }
                
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
        let batches = try batchResolver.resolveBatches(for: [item], in: entries, using: effectiveEngineSelector)
        guard let batch = batches.first else {
            throw ArchiveError.extractionFailed("Could not resolve batch")
        }
        let extractor = ArchiveExtractor(
            archiveEngineSelector: effectiveEngineSelector,
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
            guard let batch = try batchResolver.resolveBatches(for: [item], in: entries, using: effectiveEngineSelector).first else {
                throw ArchiveError.extractionFailed("Could not resolve batch")
            }
            let extractor = ArchiveExtractor(
                archiveEngineSelector: effectiveEngineSelector,
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
        } catch ArchiveError.passwordCancelled {
            tempDirectories.append(contentsOf: tempDirs.all)
            let outcome = passwordCancelledOutcome()
            if case .failed(let message) = outcome { self.error = message }
            progressCenter.finish(jobId, outcome)
            throw ArchiveError.passwordCancelled
        } catch {
            extractLog.error(error)
            tempDirectories.append(contentsOf: tempDirs.all)
            progressCenter.finish(jobId, .failed(error.localizedDescription))
            throw error
        }
    }

    /// True when `items` selects every top-level entry of the archive — the
    /// selection is the whole archive, so extraction behaves like
    /// "Extract archive" and the smart folder rule applies.
    private func coversWholeArchive(_ items: [ArchiveItem]) -> Bool {
        guard let root else { return false }
        let topLevel = entries.values.filter {
            $0.parent == root.id || ($0.parent == nil && $0.type != .root)
        }
        guard !topLevel.isEmpty else { return false }
        let selectedIDs = Set(items.map(\.id))
        return topLevel.allSatisfy { selectedIDs.contains($0.id) }
    }

    /// Extracts the given set of items to the given destination. This is usually triggered by the
    /// user from within the UI
    /// - Parameters:
    ///   - items: items to extract
    ///   - destination: destination folder
    ///   - smart: whether to decide for the user that the extraction needs a
    ///     container folder named after the archive. The caller owns that
    ///     decision: a menu entry that already names the folder it creates
    ///     passes `false`, everything else passes `Keys.smartExtractionEnabled()`.
    public func extract(
        items: [ArchiveItem],
        to destination: URL,
        smart: Bool
    ) {
        updateStatus(.processing)

        let tempDirs = ExtractionTempDirectories()
        let extractor = ArchiveExtractor(
            archiveEngineSelector: effectiveEngineSelector,
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
                let batches = try batchResolver.resolveBatches(for: items, in: entries, using: effectiveEngineSelector)
                // "Extract selected" with the whole archive selected behaves
                // like "Extract archive": the smart folder rule applies. A
                // partial selection is extracted as picked, into the destination
                // as-is — the user chose exactly those entries.
                // The smart folder is created below, before the extractor starts
                // access on it — so the user-picked destination has to be held
                // accessible from here on, or the directory creation fails for
                // sandboxed destinations.
                let didAccessDestination = destination.startAccessingSecurityScopedResource()
                defer { if didAccessDestination { destination.stopAccessingSecurityScopedResource() } }

                var target = destination
                if smart, coversWholeArchive(items) {
                    let archiveUrl = url
                    target = SmartExtraction.containerFolder(
                        for: entries,
                        archiveName: archiveUrl.map { archiveTypeDetector.getNameWithoutExtension(for: $0) } ?? "Archive",
                        destination: destination
                    ) ?? destination
                    if target != destination {
                        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                    }
                }
                let result = try await extractor.extract(
                    batches: batches,
                    to: target,
                    onProgress: makeEngineProgress(jobId: jobId, cancelFlag: cancelFlag)
                )
                tempDirectories.append(contentsOf: result.tempDirs)
                progressCenter.finish(jobId, .done)
            } catch is CancellationError {
                // partial temp output of the aborted extraction must not
                // linger — register it for the regular cache cleanup
                tempDirectories.append(contentsOf: tempDirs.all)
                progressCenter.finish(jobId, .cancelled)
            } catch ArchiveError.passwordCancelled {
                tempDirectories.append(contentsOf: tempDirs.all)
                let outcome = passwordCancelledOutcome()
                if case .failed(let message) = outcome { self.error = message }
                progressCenter.finish(jobId, outcome)
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
    
    /// Extracts the whole archive to the given destination.
    /// - Parameters:
    ///   - destination: destination folder
    ///   - smart: see `extract(items:to:smart:)`
    public func extract(to destination: URL, smart: Bool) {
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

                // The smart folder is created below, before the extractor starts
                // access on it — so the user-picked destination has to be held
                // accessible from here on, or the directory creation fails for
                // sandboxed destinations.
                let didAccessDestination = destination.startAccessingSecurityScopedResource()
                defer { if didAccessDestination { destination.stopAccessingSecurityScopedResource() } }

                var target = destination
                if smart {
                    // Folder name from the archive file, extension stripped —
                    // compounds (tar.gz) and split parts included — so it
                    // matches the "Extract to …" folder naming.
                    target = SmartExtraction.containerFolder(
                        for: entries,
                        archiveName: archiveTypeDetector.getNameWithoutExtension(for: archiveUrl),
                        destination: destination
                    ) ?? destination
                    if target != destination {
                        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                    }
                }

                let extractor = ArchiveExtractor(
                    archiveEngineSelector: effectiveEngineSelector,
                    passwordResolver: makePasswordResolver()
                )
                try await extractor.extractAll(
                    archiveUrl,
                    archiveTypeId: archiveTypeId,
                    to: target,
                    onProgress: makeEngineProgress(jobId: jobId, cancelFlag: cancelFlag)
                )
                progressCenter.finish(jobId, .done)
            } catch is CancellationError {
                progressCenter.finish(jobId, .cancelled)
            } catch ArchiveError.passwordCancelled {
                let outcome = passwordCancelledOutcome()
                if case .failed(let message) = outcome { self.error = message }
                progressCenter.finish(jobId, outcome)
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
            archiveEngineSelector: effectiveEngineSelector,
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
                        using: effectiveEngineSelector
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
        
        guard selectedItem != nil else { return }
        let hasParent = showsParentRow

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
        guard selectedItem != nil else { return selection }
        let hasParent = showsParentRow
        
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

