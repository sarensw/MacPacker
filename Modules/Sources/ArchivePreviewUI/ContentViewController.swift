//
//  ContentView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 05.10.25.
//

import AppKit
import Core
import FinderMenu

final class ContentViewController: NSViewController, ButtonBarDelegate {
    var state: ArchiveState? {
        didSet {
            archiveViewController.state = state
        }
    }
    
    private let buttonBarViewController = ButtonBarViewController()
    private let archiveViewController = ArchiveViewController()
    
    private let breadcrumbBar = NSView()
    private let stack = NSStackView()
    
    override func viewDidLoad() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        
        breadcrumbBar.translatesAutoresizingMaskIntoConstraints = false
        breadcrumbBar.wantsLayer = true
        breadcrumbBar.layer?.borderColor = NSColor.clear.cgColor
        
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(stack)
        
        addChild(buttonBarViewController)
        let buttonBarView = buttonBarViewController.view
        buttonBarView.translatesAutoresizingMaskIntoConstraints = false
        buttonBarViewController.delegate = self
        
        addChild(archiveViewController)
        let outlineView = archiveViewController.view
        outlineView.translatesAutoresizingMaskIntoConstraints = false
        
        stack.addArrangedSubview(buttonBarView)
        stack.addArrangedSubview(outlineView)
        stack.addArrangedSubview(breadcrumbBar)
        
        NSLayoutConstraint.activate([
            buttonBarView.heightAnchor.constraint(equalToConstant: 34),
            breadcrumbBar.heightAnchor.constraint(equalToConstant: 0),
            
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            outlineView.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            outlineView.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
        ])
    }
    
    func didRequestExtractSelected() {
        guard let state else { return }
        guard let selectedItems = archiveViewController.selectedItems, !selectedItems.isEmpty else { return }
        guard let window = view.window ?? NSApp.keyWindow ?? NSApp.mainWindow else { return }
        let paths = selectedItems.compactMap(\.virtualPath)

        // Next to the archive, as the setting says, by the app: this preview
        // may not write there. Only entries of the archive itself, by their
        // paths in it — not of an archive inside it, whose paths would point
        // into the outer one.
        let nextTo = Keys.extractNextToArchiveEnabled() ? state.url?.deletingLastPathComponent() : nil
        let ask: @MainActor @Sendable () -> Void = { [weak self] in
            self?.askWhereToExtract(in: window, startingIn: nextTo) { folder in
                self?.extract(into: folder, names: selectedItems.map(\.name)) {
                    state.extract(items: selectedItems, to: folder, smart: Keys.smartExtractionEnabled())
                }
            }
        }
        if let nextTo, let archive = state.url,
           paths.count == selectedItems.count,
           selectedItems.allSatisfy({ isInOuterArchive($0, of: state) }) {
            handToTheApp(
                AppUrl(action: .extractNextToArchive, files: [archive], target: nextTo, items: paths),
                otherwise: ask)
        } else {
            ask()
        }
    }

    func didRequestExtractAll() {
        guard let state else { return }
        guard let window = view.window ?? NSApp.keyWindow ?? NSApp.mainWindow else { return }
        let topLevel = state.root?.children?.compactMap { state.entries[$0]?.name } ?? []

        // Next to the archive, as the setting says, by the app, with all its
        // settings: this preview may not write there.
        let nextTo = Keys.extractNextToArchiveEnabled() ? state.url?.deletingLastPathComponent() : nil
        let ask: @MainActor @Sendable () -> Void = { [weak self] in
            self?.askWhereToExtract(in: window, startingIn: nextTo) { folder in
                self?.extract(into: folder, names: topLevel) {
                    state.extract(to: folder, smart: Keys.smartExtractionEnabled())
                }
            }
        }
        if let nextTo, let archive = state.url {
            handToTheApp(AppUrl(action: .extractNextToArchive, files: [archive], target: nextTo), otherwise: ask)
        } else {
            ask()
        }
    }

    // MARK: - Extracting

    /// Whether `item` is an entry of the archive previewed itself, not of an
    /// archive inside it.
    private func isInOuterArchive(_ item: ArchiveItem, of state: ArchiveState) -> Bool {
        var parent = item.parent
        while let id = parent, let ancestor = state.entries[id] {
            if ancestor.type == .archive { return false }
            parent = ancestor.parent
        }
        return true
    }

    /// Hands `request` to the app through its url scheme, as the Finder
    /// extension does. `otherwise` runs when the app cannot be reached.
    private func handToTheApp(_ request: AppUrl, otherwise: @escaping @MainActor @Sendable () -> Void) {
        let scheme = Bundle.main.object(forInfoDictionaryKey: "MacPackerURLScheme") as? String ?? ""
        guard !scheme.isEmpty, let url = request.url(scheme: scheme) else {
            PreviewLog.general.error("Cannot reach the app: no url scheme in the extension's Info.plist")
            otherwise()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(url, configuration: configuration) { _, error in
            guard let error else { return }
            PreviewLog.general.error("Could not hand the extraction to the app", context: ["error": error.localizedDescription])
            Task { @MainActor in otherwise() }
        }
    }

    /// Asks for the folder to extract into, as a sheet on the preview.
    private func askWhereToExtract(in window: NSWindow, startingIn folder: URL?, then extract: @escaping @MainActor (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = folder
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url {
                extract(url)
            }
        }
    }

    /// Runs `extraction` into `folder`, and selects what it put there in
    /// Finder once it is done when Finder has no window open, as the app does.
    private func extract(into folder: URL, names: [String], _ extraction: @escaping @MainActor () -> Task<ExtractionJob.State, Never>) {
        Task { @MainActor in
            let picked = folder.startAccessingSecurityScopedResource()
            defer { if picked { folder.stopAccessingSecurityScopedResource() } }
            let before = ExtractedItems.contents(of: folder)
            guard await extraction().value == .done else { return }
            let result = ExtractedItems.find(in: folder, before: before, names: names)
            if !result.isEmpty {
                ExtractedItems.select(result)
            }
        }
    }
}
