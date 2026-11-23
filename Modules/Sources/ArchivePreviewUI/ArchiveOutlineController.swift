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

    /// The archive window.
    public static let window: Self = [.navigation, .editing, .dragOut, .quickLookPanel, .columnMenu]
    /// The Quick Look preview.
    public static let preview: Self = []
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
    private var loadingItems: Set<UUID> = []
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
        outlineView.rowSizeStyle = .small
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
        childrenCache.removeAll()
        topRows = currentTopRows()
        outlineView.reloadData()
        applySelection()
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
                    self.reload()
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
    /// what it holds below its row.
    private func openNestedArchive(_ item: ArchiveItem) {
        guard let state, loadingItems.insert(item.id).inserted else { return }
        outlineView.reloadItem(item)
        PreviewLog.general.info("Opening nested archive", context: ["name": item.name])

        Task {
            do {
                try await state.openAsync(item: item)
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
            childrenCache[item.id] = nil
            outlineView.reloadItem(item, reloadChildren: true)
            if !children(of: item).isEmpty {
                outlineView.expandItem(item)
            }
        }
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
        guard let node = item as? ArchiveItem, isUnopenedArchive(node) else { return true }
        // nothing to show yet: unpack first, and open the row when it is in
        openNestedArchive(node)
        return false
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

        let cellView = NSTableCellView()
        cellView.identifier = identifier
        // greyed out, as Finder shows a hidden file
        if item.isHidden { cellView.alphaValue = 0.5 }
        let isParent = item === parentRow

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
        return cellView
    }

    /// The icon, or a spinner while an archive inside is unpacked, and the name.
    private func addName(of item: ArchiveItem, isParent: Bool, to cellView: NSTableCellView) {
        let leadingView: NSView
        if loadingItems.contains(item.id) {
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
