//
//  ArchiveOutlineController.swift
//  MacPacker
//
//  The list of an archive's entries: one code for the archive window and the
//  Quick Look preview (#251). Each host switches on what it may do.
//

import AppKit
import Combine
import Core
import UniformTypeIdentifiers

/// What a host lets the list do. The archive window allows all of it. The
/// Quick Look preview only looks: it changes nothing, and a drag out of it
/// would need an entitlement the App Store refuses.
public struct ArchiveOutlineFeatures: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// The list shows the folder the window is in and moves through the
    /// archive: a double click goes into a folder or an archive inside, or
    /// opens a file in its app; ⌘↓ and ⌘↑; the `..` row of the Table layout.
    public static let navigation = Self(rawValue: 1 << 0)
    /// ⌫, ⌦ and Edit ▸ Delete delete the selection.
    public static let editing = Self(rawValue: 1 << 1)
    /// Rows dragged to Finder are extracted where they land.
    public static let dragOut = Self(rawValue: 1 << 2)
    /// Space shows the selection in the Quick Look panel; ↑ and ↓ move it.
    public static let quickLookPanel = Self(rawValue: 1 << 3)
    /// The header's menu shows and hides columns.
    public static let columnMenu = Self(rawValue: 1 << 4)
    /// Files dropped on the list are added: on a folder row into that folder,
    /// on a file row into its folder, on empty space into the folder shown.
    public static let dropTargets = Self(rawValue: 1 << 5)

    /// The archive window.
    public static let window: Self = [.navigation, .editing, .dragOut, .quickLookPanel, .columnMenu, .dropTargets]
    /// The Quick Look preview.
    public static let preview: Self = []
}

/// What a file dragged over the list would do, for the window to say (#251 G2).
public enum ArchiveDropHint: Equatable, Sendable {
    /// It goes into this folder: its names from the top of the archive, none
    /// for the top itself.
    case addInto([String])
    /// The archive named can't be changed, so nothing goes in.
    case cantChange(String)
    /// The archive named needs its password: a drop asks for it.
    case needsPassword(String)
    /// The archive named is being unpacked.
    case opening(String)
}

/// A file dragged over the list: it came in, left, or the drag is over,
/// dropped or not. The window shows its card that opens meanwhile.
public enum ArchiveFileDrag: Sendable {
    case entered, exited, ended
}

/// How the list lays out the entries.
public enum ArchiveOutlineLayout: Sendable {
    /// Folders and archives inside open in place on their triangle.
    case tree
    /// One folder at a time, without triangles or indent, as 7-Zip lists it.
    case table
}

@MainActor
public final class ArchiveOutlineController: NSViewController {
    public let features: ArchiveOutlineFeatures
    public var layout: ArchiveOutlineLayout {
        didSet {
            guard layout != oldValue, isViewLoaded else { return }
            applyLayout()
            reload()
        }
    }
    public var state: ArchiveState? {
        didSet {
            guard state !== oldValue else { return }
            observeState()
            reload()
        }
    }
    /// The column titles. The window passes its own strings: its app tests
    /// find the headers by the ids of the app's catalog.
    public var columnTitles: [ArchiveViewerColumn: String] = ArchiveOutlineController.defaultColumnTitles {
        didSet { applyTitles() }
    }
    /// What a right click opens; the host builds it. A right click outside the
    /// selection selects that row first.
    public var contextMenu: NSMenu? {
        didSet { outlineView.menu = contextMenu }
    }

    public let outlineView = ArchiveOutlineView()
    private let scrollView = NSScrollView()

    /// Archives inside the archive being unpacked: their row shows a spinner.
    private(set) var loadingItems: Set<UUID> = []
    /// What the list shows at its top level, taken at the last reload. The
    /// rows are read from this, never from the state's live list: between a
    /// change and the reload AppKit may still ask for a row of the list it
    /// knows, which a live list no longer has (#427).
    private var topRows: [ArchiveItem] = []
    /// Each opened folder's rows, sorted once per reload rather than for every
    /// row AppKit asks for.
    private var childrenCache: [UUID: [ArchiveItem]] = [:]
    /// The `..` row of the Table layout: a stand-in for the folder above.
    let parentRow = ArchiveItem(name: "..", virtualPath: "/", type: .root)
    private var subscriptions: Set<AnyCancellable> = []
    /// Set while the list itself puts the state's selection on its rows.
    private var applyingSelection = false
    /// The folders open when a search began, to open again when it ends.
    private var openBeforeSearch: [ArchiveItem]?
    /// Told what a file dragged over the list would do, nil once none is.
    public var onDropHint: ((ArchiveDropHint?) -> Void)?
    /// Told when a file dragged over the list comes in, leaves, or the drag is
    /// over.
    public var onFileDrag: ((ArchiveFileDrag) -> Void)?
    private var lastHint: ArchiveDropHint?
    /// Where the drop goes, as the last check of the drag found it.
    private var dropTargetItem: ArchiveItem?

    /// A file is being dragged over the list: rows that can't take it fade.
    private(set) var isDraggingOver = false
    /// The rows a drag opened by hovering, in the order it opened them.
    private var openedByDrag: [ArchiveItem] = []
    /// The drag those rows belong to: one that comes back finds them open.
    private var dragSequence: Int?
    /// Archives inside unpacked while the drag rests on them, without a
    /// spinner: AppKit's own hover expand finds them ready.
    private(set) var quietLoads: Set<UUID> = []
    /// A reload was asked for while a file was over the list.
    private var reloadsWhenTheDragEnds = false
    /// The archive whose top level was looked at for a single folder to open.
    private var openedSingleFolderOf: ObjectIdentifier?
    /// An archive inside being unpacked for the drag hovering over it, which
    /// stops once the drag moves on.
    private var hoverLoad: (item: ArchiveItem, cancel: ExtractionCancelFlag)?

    /// The folders open when a save began, by name, to open again once the
    /// archive has been read anew; and the rereads already done.
    private var openAtSave: [[String]] = []
    private var seenRereads = 0
    private var dragOut: ArchiveDragOut?

    public init(features: ArchiveOutlineFeatures, layout: ArchiveOutlineLayout) {
        self.features = features
        self.layout = layout
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    public static var defaultColumnTitles: [ArchiveViewerColumn: String] {
        [
            .name: String(localized: "Name", bundle: .module, comment: "Column that shows the name of the archive files"),
            .compressedSize: String(localized: "Packed Size", bundle: .module, comment: "Column that shows the packed size of the archive files"),
            .uncompressedSize: String(localized: "Size", bundle: .module, comment: "Column that shows the unpacked size of the archive files"),
            .modificationDate: String(localized: "Date Modified", bundle: .module, comment: "Column that shows the date the file was modified"),
            .posixPermissions: String(localized: "Permissions", bundle: .module, comment: "Column that shows the Unix permissions of the archive files, such as -rw-r--r--"),
        ]
    }

    public override func loadView() {
        let clipView = NSClipView()
        clipView.documentView = outlineView
        scrollView.contentView = clipView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        outlineView.controller = self
        outlineView.headerView = NSTableHeaderView()
        outlineView.allowsColumnReordering = false
        outlineView.allowsColumnResizing = true
        outlineView.allowsMultipleSelection = true
        outlineView.rowHeight = 22
        outlineView.autosaveTableColumns = false
        outlineView.usesAlternatingRowBackgroundColors = true
        outlineView.selectionHighlightStyle = .regular
        outlineView.style = .fullWidth
        // the names at the system size, as Finder lists them: `.small` set
        // them in 11 pt, beside the other columns' 13
        outlineView.rowSizeStyle = .custom
        outlineView.gridStyleMask = []
        outlineView.setAccessibilityIdentifier("archive.list")
        createColumns()
        // after the columns: setting up their sort is no choice of the user's
        outlineView.delegate = self
        outlineView.dataSource = self
        if features.contains(.dragOut) {
            outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)
        }
        if features.contains(.navigation) {
            outlineView.target = self
            outlineView.doubleAction = #selector(doubleClicked(_:))
        }
        outlineView.menu = contextMenu
        applyLayout()

        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        reload()
    }

    // MARK: - Columns

    /// The columns in the window's order, shown or hidden as the window shows
    /// them, sorted by the choice made in either: the settings live in the app
    /// group the preview reads (#251 B9, B10).
    private func createColumns() {
        let columns: [(ArchiveViewerColumn, CGFloat, ArchiveSortOrder)] = [
            (.name, 300, .name),
            (.compressedSize, 100, .compressedSize),
            (.uncompressedSize, 100, .uncompressedSize),
            (.modificationDate, 150, .modificationDate),
            (.posixPermissions, 80, .posixPermissions),
        ]
        for (column, width, order) in columns {
            let tableColumn = NSTableColumn(identifier: column.identifier)
            tableColumn.width = width
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: order.rawValue, ascending: true)
            if column == .name { tableColumn.resizingMask = .userResizingMask }
            outlineView.addTableColumn(tableColumn)
        }
        outlineView.outlineTableColumn = outlineView.tableColumn(withIdentifier: ArchiveViewerColumn.name.identifier)
        applyTitles()
        applyColumnVisibility()
        let sortOrder = Keys.sortOrder()
        outlineView.sortDescriptors = [NSSortDescriptor(key: sortOrder.column.rawValue, ascending: sortOrder.ascending)]
    }

    private func applyTitles() {
        for column in outlineView.tableColumns {
            if let id = ArchiveViewerColumn(identifier: column.identifier), let title = columnTitles[id] {
                column.title = title
            }
        }
    }

    /// Shows and hides the columns as the settings say. The window calls this
    /// when one changes.
    public func applyColumnVisibility() {
        for column in outlineView.tableColumns {
            if let key = ArchiveViewerColumn(identifier: column.identifier)?.visibilitySetting {
                column.isHidden = !Keys.showsColumn(key)
            }
        }
    }

    // MARK: - Layout and reload

    private func applyLayout() {
        // Table: no room for triangles, so the cells sit where a table puts them
        outlineView.indentationPerLevel = layout == .table ? 0 : 16
    }

    /// Lists the state anew: a new snapshot, the opened folders kept, the
    /// state's selection back on its rows.
    public func reload() {
        guard isViewLoaded else { return }
        // A search lists flat results, which drops the folders opened in the
        // tree; they open again once it is cleared (#251 D2).
        let searching = features.contains(.navigation) && state?.isSearching == true
        if searching, openBeforeSearch == nil {
            openBeforeSearch = openItems()
        }
        // A save reads the archive anew: every entry is a new object, and the
        // folders open when the save began are found again by name (#251 G7).
        var openBeforeReread: [[String]] = []
        let reread = state.map { $0.rereadsAfterSave != seenRereads } ?? false
        if let state, state.rereadsAfterSave != seenRereads {
            seenRereads = state.rereadsAfterSave
            openBeforeReread = openAtSave
            openAtSave = []
        }
        childrenCache.removeAll()
        topRows = currentTopRows()
        outlineView.reloadData()
        if !searching, let open = openBeforeSearch {
            openBeforeSearch = nil
            for item in open { outlineView.expandItem(item) }
        }
        for names in openBeforeReread { expandRow(at: names) }
        // An archive holding a single folder at its top opens it in the tree,
        // one click less to what it holds (#251 A1). Once per archive opened:
        // not on a save's rereading, which keeps what was left open or shut.
        if let state, let root = state.root, !topRows.isEmpty, openedSingleFolderOf != ObjectIdentifier(root) {
            openedSingleFolderOf = ObjectIdentifier(root)
            if !reread, layout == .tree, !searching, state.selectedItem == nil || state.selectedItem === root,
               topRows.count == 1, let only = topRows.first, only.isFolder {
                outlineView.expandItem(only)
            }
        }
        applySelection()
    }

    /// The names of the rows from the top of the list down to `item`, read
    /// off the rows themselves, which still hold the entries of before.
    private func namesOfRow(_ item: ArchiveItem) -> [String] {
        var names = [item.name]
        var parent = outlineView.parent(forItem: item)
        while let row = parent as? ArchiveItem {
            names.insert(row.name, at: 0)
            parent = outlineView.parent(forItem: row)
        }
        return names
    }

    /// Opens the row those names lead to, if the list still has it.
    private func expandRow(at names: [String]) {
        var item: ArchiveItem?
        for name in names {
            guard let next = children(of: item).first(where: { $0.name == name && $0 !== parentRow }) else { return }
            outlineView.expandItem(next)
            item = next
        }
    }

    /// The folders and archives inside that are open, outer ones first.
    private func openItems() -> [ArchiveItem] {
        (0..<outlineView.numberOfRows)
            .compactMap { outlineView.item(atRow: $0) as? ArchiveItem }
            .filter { outlineView.isItemExpanded($0) }
    }

    private func currentTopRows() -> [ArchiveItem] {
        guard let state else { return [] }
        guard features.contains(.navigation) else {
            return state.root.map(state.displayedChildren(of:)) ?? []
        }
        let parent = layout == .table && state.showsParentRow ? [parentRow] : []
        return parent + (state.childItems ?? [])
    }

    private func observeState() {
        subscriptions.removeAll()
        guard let state else { return }
        // Once the state has settled: what changed is read in one go.
        state.$isReloadNeeded
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let state = self.state, state.isReloadNeeded else { return }
                    // AppKit's drop target goes with a reload, and the drop with
                    // it: an archive inside that hovering opened asks for one
                    if self.isDraggingOver {
                        self.reloadsWhenTheDragEnds = true
                    } else {
                        self.reload()
                    }
                    state.isReloadNeeded = false
                }
            }
            .store(in: &subscriptions)
        state.$selectedItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.applySelection() }
            }
            .store(in: &subscriptions)
        if features.contains(.dropTargets) {
            // A read-only archive leaves a dropped file to the window, whose one
            // card opens it: registered, the list would take every drag over it.
            state.$canBeEdited
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] editable in
                    MainActor.assumeIsolated {
                        guard let outline = self?.outlineView else { return }
                        if editable { outline.registerForDraggedTypes([.fileURL]) } else { outline.unregisterDraggedTypes() }
                    }
                }
                .store(in: &subscriptions)
        }
        // Before the save reads the archive anew, while the rows still hold the
        // entries of before.
        seenRereads = state.rereadsAfterSave
        state.$isSaving
            .filter { $0 }
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.openAtSave = self.openItems().map(self.namesOfRow)
                }
            }
            .store(in: &subscriptions)
    }

    /// Puts the state's selection on the rows that show it, and brings the
    /// first one into view: ⌘↑ selects the folder just left (#426).
    private func applySelection() {
        guard let state, isViewLoaded else { return }
        let rows = IndexSet(state.selectedItems.compactMap { item -> Int? in
            let row = outlineView.row(forItem: item)
            return row >= 0 ? row : nil
        })
        guard rows != outlineView.selectedRowIndexes else { return }
        applyingSelection = true
        outlineView.selectRowIndexes(rows, byExtendingSelection: false)
        applyingSelection = false
        if let first = rows.first { outlineView.scrollRowToVisible(first) }
    }

    /// The entries of the selected rows; the `..` row is none.
    public var selectedItems: [ArchiveItem] {
        outlineView.selectedRowIndexes.compactMap { outlineView.item(atRow: $0) as? ArchiveItem }
            .filter { $0 !== parentRow }
    }

    // MARK: - Actions

    @objc private func doubleClicked(_ sender: Any?) {
        let row = outlineView.clickedRow
        guard row >= 0, let item = outlineView.item(atRow: row) as? ArchiveItem else { return }
        if item === parentRow {
            state?.openParent()
        } else {
            state?.open(item: item)
        }
    }

    /// ⌘↓: into the selected folder or archive, or the selected file opened.
    func openSelected() {
        guard features.contains(.navigation), let item = selectedItems.first else { return }
        state?.open(item: item)
    }

    /// ⌘↑: the folder above, with the folder just left selected (#426).
    func goUp() {
        guard features.contains(.navigation) else { return }
        state?.openParent()
    }

    /// Space: the Quick Look panel opens on the selection, or closes.
    func toggleQuickLook() {
        guard features.contains(.quickLookPanel), let state else { return }
        if state.previewItemUrl != nil {
            state.previewItemUrl = nil
        } else {
            state.updateSelectedItemForQuickLook()
        }
    }

    var canDeleteSelection: Bool {
        guard features.contains(.editing), let state else { return false }
        return state.canRemove(state.selectedItems)
    }

    /// ⌫, ⌦ and Edit ▸ Delete.
    func deleteSelection() {
        guard canDeleteSelection, let state else { return }
        state.remove(items: state.selectedItems)
    }

    // MARK: - Archives inside

    /// An archive inside the archive gets a triangle before anything is known
    /// about what it holds; opening it unpacks it.
    private func isUnopenedArchive(_ item: ArchiveItem) -> Bool {
        guard let state, item.type == .file, item.children == nil else { return false }
        // Extension only: the entry is still inside the archive, no bytes to sniff
        return state.looksLikeArchive(url: URL(fileURLWithPath: item.name))
    }

    /// Unpacks an archive inside the archive to a temporary place and hangs
    /// what it holds below its row; the window stays where it is (#251 B15).
    private func openNestedArchive(_ item: ArchiveItem, quietly: Bool = false) {
        guard let state, loadingItems.insert(item.id).inserted else { return }
        if quietly { quietLoads.insert(item.id) } else { refresh(item) }
        PreviewLog.general.info("Opening nested archive", context: ["name": item.name, "quietly": String(quietly)])
        // opened by a drag hovering over it: no prompt, and it stops once the drag moves on
        let duringDrag = isDraggingOver
        let cancel = ExtractionCancelFlag()
        if duringDrag { hoverLoad = (item, cancel) }

        Task {
            do {
                try await state.openInPlace(item: item, askingForPassword: !duringDrag, cancel: duringDrag ? cancel : nil)
                PreviewLog.general.info("Nested archive opened", context: [
                    "name": item.name,
                    "items": "\(item.children?.count ?? 0)",
                ])
            } catch {
                // The row stays closed and can be opened again.
                PreviewLog.general.error("Nested archive failed to open", context: [
                    "name": item.name,
                    "error": error.localizedDescription,
                ])
            }
            loadingItems.remove(item.id)
            // unpacked quietly, it waits for the hover's own expand
            let quiet = quietLoads.remove(item.id) != nil
            if hoverLoad?.item === item { hoverLoad = nil }
            childrenCache[item.id] = nil
            refresh(item)
            // a drag that moved on leaves it closed
            if !quiet, !children(of: item).isEmpty, !(duringDrag && cancel.isCancelled) {
                outlineView.expandItem(item)
            }
        }
    }

    /// Draws `item`'s row anew: its spinner, its lock, its triangle. Under a
    /// drag only its cells: reloaded as an item, the row loses the drop AppKit
    /// is aiming at it, and the drop never arrives. Expanding asks for the
    /// children anyway.
    private func refresh(_ item: ArchiveItem) {
        guard isDraggingOver else {
            outlineView.reloadItem(item, reloadChildren: true)
            return
        }
        let row = outlineView.row(forItem: item)
        guard row >= 0 else { return }
        outlineView.reloadData(forRowIndexes: IndexSet(integer: row),
                               columnIndexes: IndexSet(integersIn: 0..<outlineView.numberOfColumns))
    }

    fileprivate func children(of item: Any?) -> [ArchiveItem] {
        guard let node = item as? ArchiveItem else { return topRows }
        guard node !== parentRow, let state else { return [] }
        if let cached = childrenCache[node.id] { return cached }
        let rows = state.displayedChildren(of: node)
        childrenCache[node.id] = rows
        return rows
    }
}

// MARK: - Data source and delegate

extension ArchiveOutlineController: NSOutlineViewDataSource, NSOutlineViewDelegate {

    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        children(of: item).count
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        let rows = children(of: item)
        // a snapshot cannot shrink under AppKit; the guard only keeps a slip harmless
        return rows.indices.contains(index) ? rows[index] : parentRow
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard layout == .tree, let node = item as? ArchiveItem, node !== parentRow else { return false }
        // search results come from every level at once: a flat list
        if features.contains(.navigation), state?.isSearching == true { return false }
        return !children(of: node).isEmpty || isUnopenedArchive(node)
    }

    public func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
        guard let node = item as? ArchiveItem else { return true }
        if isDraggingOver, let state {
            // a drag opens only what it can drop into, and asks for no password
            if !state.canChange(node) || state.lockedNested.contains(node.id) { return false }
        }
        guard isUnopenedArchive(node) else { return true }
        if quietLoads.remove(node.id) != nil {
            // the hover's expand came before the unpacking was done: show it
            // unpacking, and open the row when it is in
            refresh(node)
            return false
        }
        // nothing to show yet: unpack first, and open the row when it is in
        openNestedArchive(node)
        return false
    }

    public func outlineViewItemDidExpand(_ notification: Notification) {
        if isDraggingOver, let item = notification.userInfo?["NSObject"] as? ArchiveItem {
            openedByDrag.append(item)
        }
    }

    // MARK: - Drops

    /// Where a file dropped on `row` goes: a folder or an archive inside takes
    /// it, a file row hands it to its folder, empty space to the folder shown.
    private func dropTarget(for row: ArchiveItem?) -> ArchiveItem? {
        guard let state else { return nil }
        let shown = state.selectedItem ?? state.root
        guard let row, row !== parentRow else { return shown }
        if row.isFolder || row.archiveTypeId != nil || isUnopenedArchive(row) { return row }
        // its own folder, also for a search result listed away from it
        return row.parent.flatMap { state.entries[$0] } ?? state.root
    }

    private func hint(_ hint: ArchiveDropHint?) {
        guard hint != lastHint else { return }
        lastHint = hint
        onDropHint?(hint)
    }

    private func canTakeDrop(_ row: ArchiveItem) -> Bool {
        guard let state, let target = dropTarget(for: row) else { return false }
        return state.canChange(target)
    }

    public func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        guard features.contains(.dropTargets), let state, !(info.draggingSource is ArchiveOutlineView) else { return [] }
        if !isDraggingOver { beginDragOver(info) }
        var row = item as? ArchiveItem
        if index != NSOutlineViewDropOnItemIndex {
            // between two rows AppKit proposes their folder: the row under the
            // pointer decides, an archive inside's own row included
            let at = outlineView.row(at: outlineView.convert(info.draggingLocation, from: nil))
            row = at >= 0 ? outlineView.item(atRow: at) as? ArchiveItem : nil
        }
        guard let target = dropTarget(for: row) else { return [] }
        // the hover's archive stops unpacking once the drag has moved on
        if let load = hoverLoad, load.item !== row, !(row.map { isInside($0, load.item) } ?? false) {
            load.cancel.cancel()
            hoverLoad = nil
        }
        // An archive inside under the pointer is unpacked while the drag rests
        // on it: AppKit's own hover expand then finds it ready, and opens it
        // as it opens a folder, with the same flash after the same wait.
        if let row, row === target, isUnopenedArchive(row), state.canChange(row),
           !state.lockedNested.contains(row.id), !loadingItems.contains(row.id) {
            openNestedArchive(row, quietly: true)
        }
        // the folder row itself is the target, its block outlined; the folder
        // shown, or one with no row (a search result's), is the whole list
        let shown = state.selectedItem ?? state.root
        let targetRow: ArchiveItem? = target === shown || outlineView.row(forItem: target) < 0 ? nil : target
        outlineView.setDropItem(targetRow, dropChildIndex: NSOutlineViewDropOnItemIndex)
        dropTargetItem = target

        guard state.canChange(target) else {
            let blocking = state.archiveThatCantBeChanged(down: target)
            hint(.cantChange(blocking?.name ?? state.name ?? ""))
            return []
        }
        if loadingItems.contains(target.id), !quietLoads.contains(target.id) {
            hint(.opening(target.name))
        } else if state.lockedNested.contains(target.id) {
            hint(.needsPassword(target.name))
        } else {
            hint(.addInto(target === shown ? [] : state.namesFromTop(of: target) ?? []))
        }
        return .copy
    }

    public func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        let target = dropTargetItem
        PreviewLog.general.debug("Drop on the list", context: [
            "target": target?.name ?? "none",
            "canChange": String(target.map { state?.canChange($0) ?? false } ?? false),
        ])
        finishDrag(droppedInto: target)
        onFileDrag?(.ended)
        guard let state, let target, state.canChange(target),
              let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return false }
        PreviewLog.general.notice("Files dropped on the list", context: ["files": String(urls.count)])
        guard isUnopenedArchive(target) else {
            state.add(urls: urls, into: target)
            return true
        }
        // a closed archive inside: unpacked first, its password asked now, after the drop
        quietLoads.remove(target.id)
        loadingItems.insert(target.id)
        outlineView.reloadItem(target)
        Task {
            do {
                try await state.openInPlace(item: target)
            } catch {
                PreviewLog.general.error("An archive inside a drop went into could not be opened", context: ["name": target.name])
            }
            loadingItems.remove(target.id)
            childrenCache[target.id] = nil
            outlineView.reloadItem(target, reloadChildren: true)
            // only once it is open: without its password nothing goes in
            if target.children != nil { state.add(urls: urls, into: target) }
        }
        return true
    }

    private func isInside(_ item: ArchiveItem, _ folder: ArchiveItem) -> Bool {
        var parent = outlineView.parent(forItem: item)
        while let current = parent as? ArchiveItem {
            if current === folder { return true }
            parent = outlineView.parent(forItem: current)
        }
        return false
    }

    private func beginDragOver(_ info: NSDraggingInfo) {
        isDraggingOver = true
        if info.draggingSequenceNumber != dragSequence {
            // another drag: what an earlier one opened and left open stays open
            dragSequence = info.draggingSequenceNumber
            openedByDrag = []
        }
        onFileDrag?(.entered)
        restyleRows()
    }

    /// The drag left the list, or ended over it without a drop.
    func dragLeft(ended: Bool) {
        if isDraggingOver { PreviewLog.general.debug("Drag left the list", context: ["ended": String(ended)]) }
        if ended { finishDrag() } else { leaveDrag() }
        onFileDrag?(ended ? .ended : .exited)
    }

    /// The drag left the list: the rows look as before, and what it opened
    /// stays open, for a drag that comes back (user, 2026-11-24: a drag that
    /// strayed out of the window closed every level opened on the way).
    private func leaveDrag(keepingLoadOf target: ArchiveItem? = nil) {
        guard isDraggingOver else { return }
        isDraggingOver = false
        // an archive inside still being unpacked for the hover keeps on if the
        // file was dropped on it: the drop's own open waits for it
        if let load = hoverLoad, load.item !== target { load.cancel.cancel() }
        hoverLoad = nil
        dropTargetItem = nil
        hint(nil)
        if reloadsWhenTheDragEnds {
            reloadsWhenTheDragEnds = false
            reload()
        } else {
            restyleRows()
        }
    }

    /// The drag is over: the rows it opened close again, except the ones the
    /// file went into.
    func finishDrag(droppedInto target: ArchiveItem? = nil) {
        leaveDrag(keepingLoadOf: target)
        for item in openedByDrag.reversed() where !(target.map { $0 === item || isInside($0, item) } ?? false) {
            outlineView.collapseItem(item)
        }
        openedByDrag = []
        dragSequence = nil
    }

    /// Redraws the rows' text: faded while a drag can't drop on them.
    private func restyleRows() {
        guard outlineView.numberOfRows > 0 else { return }
        outlineView.reloadData(forRowIndexes: IndexSet(integersIn: 0..<outlineView.numberOfRows),
                               columnIndexes: IndexSet(integersIn: 0..<outlineView.numberOfColumns))
    }

    public func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !applyingSelection else { return }
        state?.select(selectedItems)
    }

    /// A click on a header sorts by that column, here and in the other list:
    /// the choice goes to the app group both read.
    public func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = outlineView.sortDescriptors.first,
              let key = descriptor.key, let column = ArchiveSortOrder(rawValue: key) else { return }
        let current = Keys.sortOrder()
        if current.column != column || current.ascending != descriptor.ascending {
            UserDefaults.macPackerShared.set(key, forKey: Keys.defaultOrderColumn)
            UserDefaults.macPackerShared.set(descriptor.ascending, forKey: Keys.defaultOrderColumnAscending)
        }
        if features.contains(.navigation) { state?.loadChildren() }
        reload()
    }

    public func outlineView(_ outlineView: NSOutlineView, userCanChangeVisibilityOf column: NSTableColumn) -> Bool {
        features.contains(.columnMenu) && column.identifier != ArchiveViewerColumn.name.identifier
    }

    public func outlineView(_ outlineView: NSOutlineView, userDidChangeVisibilityOf columns: [NSTableColumn]) {
        for column in columns {
            if let key = ArchiveViewerColumn(identifier: column.identifier)?.visibilitySetting {
                UserDefaults.macPackerShared.set(!column.isHidden, forKey: key)
            }
        }
    }

    public func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard features.contains(.dragOut), let state,
              let item = item as? ArchiveItem, item !== parentRow else { return nil }
        // a row inside a folder dragged along comes with the folder (#251 C4)
        let dragged = state.selectedItems.contains { $0 === item } ? state.selectedItems : [item]
        guard state.withoutNested(dragged).contains(where: { $0 === item }) else { return nil }
        if dragOut?.state !== state { dragOut = ArchiveDragOut(state: state) }
        let type = (item.ext.isEmpty ? UTType.data : UTType(filenameExtension: item.ext))?.identifier
            ?? UTType.data.identifier
        let provider = NSFilePromiseProvider(fileType: type, delegate: dragOut!)
        provider.userInfo = item
        return provider
    }

    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let identifier = tableColumn?.identifier,
              let column = ArchiveViewerColumn(identifier: identifier),
              let item = item as? ArchiveItem else { return nil }

        // Dragged out, a row shows its icon and its name, as in Finder: the
        // other columns' cells add nothing to the image.
        let cellView = column == .name ? NSTableCellView() : DetailCellView()
        cellView.identifier = identifier
        // greyed out, as Finder shows a hidden file
        if item.isHidden { cellView.alphaValue = 0.5 }
        let isParent = item === parentRow
        // while a drag is over the list, the text of rows that can't take it fades
        let faded = isDraggingOver && !isParent && !canTakeDrop(item)

        switch column {
        case .name:
            addName(of: item, isParent: isParent, to: cellView)
        case .compressedSize, .uncompressedSize:
            addSecondaryText(EntryText.size(of: item, packed: column == .compressedSize), to: cellView, alignedRight: true)
        case .modificationDate:
            if let date = item.modificationDate {
                addSecondaryText(EntryText.date(date), to: cellView, alignedRight: false)
            }
        case .posixPermissions:
            if let permissions = item.posixPermissions {
                addSecondaryText(EntryText.permissions(permissions), to: cellView, alignedRight: false)
            }
        }
        if faded {
            for case let text as NSTextField in cellView.subviews { text.textColor = .tertiaryLabelColor }
        }
        return cellView
    }

    /// The icon, or a spinner while an archive inside is unpacked, and the name.
    private func addName(of item: ArchiveItem, isParent: Bool, to cellView: NSTableCellView) {
        let leadingView: NSView
        if loadingItems.contains(item.id), !quietLoads.contains(item.id) {
            let spinner = NSProgressIndicator()
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.isIndeterminate = true
            spinner.startAnimation(nil)
            leadingView = spinner
        } else {
            let icon: NSImage
            if isParent {
                icon = NSWorkspace.shared.icon(for: .folder)
            } else if let cached = item.icon {
                icon = cached
            } else {
                icon = item.isFolder ? NSWorkspace.shared.icon(for: .folder)
                    : NSWorkspace.shared.icon(forFileType: (item.name as NSString).pathExtension)
                item.icon = icon
            }
            icon.size = NSSize(width: 16, height: 16)
            let imageView = NSImageView(image: icon)
            imageView.imageScaling = .scaleProportionallyDown
            // An image view takes image and file drags of its own: over a
            // row's icon a file dragged over the list went to the icon, which
            // refused it, and the list took it for a drag that left.
            imageView.unregisterDraggedTypes()
            cellView.imageView = imageView
            leadingView = imageView
        }
        leadingView.translatesAutoresizingMaskIntoConstraints = false
        leadingView.setContentHuggingPriority(.required, for: .horizontal)
        leadingView.setContentCompressionResistancePriority(.required, for: .horizontal)

        let label = NSTextField(labelWithString: isParent ? ".." : item.name)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.usesSingleLineMode = true
        label.lineBreakMode = .byTruncatingTail
        cellView.textField = label
        // an archive inside that a drag could not open without its password
        if state?.lockedNested.contains(item.id) == true,
           let lock = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil) {
            let attachment = NSTextAttachment()
            attachment.image = lock
            let text = NSMutableAttributedString(string: item.name + " ")
            text.append(NSAttributedString(attachment: attachment))
            label.attributedStringValue = text
        }

        cellView.addSubview(leadingView)
        cellView.addSubview(label)
        NSLayoutConstraint.activate([
            leadingView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 2),
            leadingView.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            leadingView.widthAnchor.constraint(equalToConstant: 16),
            leadingView.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: leadingView.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: cellView.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
        ])
    }

    /// A size, a date or permissions: grey, as Finder shows them.
    private func addSecondaryText(_ text: String, to cellView: NSTableCellView, alignedRight: Bool) {
        let textField = NSTextField(labelWithString: text)
        cellView.addSubview(textField)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.textColor = .secondaryLabelColor
        if alignedRight {
            textField.alignment = .right
            NSLayoutConstraint.activate([
                textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -8),
                textField.leadingAnchor.constraint(greaterThanOrEqualTo: cellView.leadingAnchor, constant: 8),
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                textField.trailingAnchor.constraint(lessThanOrEqualTo: cellView.trailingAnchor, constant: -8),
                textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            ])
        }
    }
}

// MARK: - The outline view

/// The list's keys and its Edit ▸ Delete, each only as far as the host's
/// features allow.
public final class ArchiveOutlineView: NSOutlineView, NSMenuItemValidation {
    weak var controller: ArchiveOutlineController?
    nonisolated(unsafe) private var keyMonitor: Any?

    deinit {
        if let keyMonitor {
            MainActor.assumeIsolated { NSEvent.removeMonitor(keyMonitor) }
        }
    }

    public override func keyDown(with event: NSEvent) {
        guard let controller else { return super.keyDown(with: event) }
        let features = controller.features
        let command = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 49 where features.contains(.quickLookPanel):
            controller.toggleQuickLook()
        case 51, 117:
            if features.contains(.editing) { controller.deleteSelection() } else { super.keyDown(with: event) }
        case 125 where command && features.contains(.navigation):
            controller.openSelected()
        case 126 where command && features.contains(.navigation):
            controller.goUp()
        default:
            super.keyDown(with: event)
        }
    }

    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = super.draggingEntered(sender)
        PreviewLog.general.debug("Drag entered the list", context: ["operation": String(operation.rawValue)])
        return operation
    }

    public override func draggingExited(_ sender: NSDraggingInfo?) {
        super.draggingExited(sender)
        controller?.dragLeft(ended: false)
    }

    /// No `super`: NSTableView has no `draggingEnded(_:)` of its own. Called,
    /// it threw at the end of every drag over the list, and AppKit, swallowing
    /// it, handed the window no drag ever after.
    public override func draggingEnded(_ sender: NSDraggingInfo) {
        controller?.dragLeft(ended: true)
    }

    /// The controller closes what a drag opened, all but the rows the file
    /// went into.
    public override func shouldCollapseAutoExpandedItems(forDeposited deposited: Bool) -> Bool {
        false
    }

    /// A right click outside the selection acts on the row clicked: it is
    /// selected first, as in Finder.
    public override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if row >= 0, !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return super.menu(for: event)
    }

    /// With the Quick Look panel open, the panel has the keys: ↑ and ↓ are
    /// passed to the list, which moves the selection the panel shows.
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        guard window != nil, controller?.features.contains(.quickLookPanel) == true else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 125 || event.keyCode == 126 else { return event }
            // a local monitor runs on the main thread
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.controller?.state?.previewItemUrl != nil else { return false }
                self.moveSelection(with: event)
                return true
            }
            return handled ? nil : event
        }
    }

    private func moveSelection(with event: NSEvent) {
        super.keyDown(with: event)
    }

    /// Edit ▸ Delete sends `delete:` down the responder chain.
    @objc func delete(_ sender: Any?) {
        controller?.deleteSelection()
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(delete(_:)) {
            return controller?.canDeleteSelection ?? false
        }
        return true
    }
}

// MARK: - Dragging out

/// Delivers a row dragged out of the list where Finder drops it. AppKit asks
/// on its own queue; the extraction runs on the main actor, with the state.
final class ArchiveDragOut: NSObject, NSFilePromiseProviderDelegate, @unchecked Sendable {
    let state: ArchiveState
    private let queue = OperationQueue()

    init(state: ArchiveState) {
        self.state = state
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        (filePromiseProvider.userInfo as? ArchiveItem)?.name ?? "unknown"
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let done = Completion(call: completionHandler)
        guard let item = filePromiseProvider.userInfo as? ArchiveItem else {
            PreviewLog.drag.error("A dragged row carries no entry")
            return done.call(NSError(domain: "Drag", code: 1))
        }
        let state = self.state
        Task { @MainActor in
            do {
                try await state.fulfillDrag(item: item, to: url)
                done.call(nil)
            } catch {
                PreviewLog.drag.error("A dragged row could not be delivered", context: ["error": error.localizedDescription])
                done.call(error)
            }
        }
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        queue
    }

    /// AppKit's completion handler, handed to the main actor.
    private struct Completion: @unchecked Sendable {
        let call: (Error?) -> Void
    }
}

/// A cell beside the name. It adds nothing to the image of a row dragged out:
/// without an `imageView` or `textField` of its own, AppKit would take a
/// snapshot of the whole cell, and a dragged row would show as a band across
/// every column.
final class DetailCellView: NSTableCellView {
    override var draggingImageComponents: [NSDraggingImageComponent] { [] }
}
