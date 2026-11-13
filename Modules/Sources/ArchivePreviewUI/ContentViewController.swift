//
//  ContentView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 05.10.25.
//

import AppKit
import Core

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

        askWhereToExtract(in: window, startingIn: folderNextToTheArchive(of: state)) { [weak self] folder in
            self?.extract(into: folder, names: selectedItems.map(\.name)) {
                state.extract(items: selectedItems, to: folder, smart: Keys.smartExtractionEnabled())
            }
        }
    }

    func didRequestExtractAll() {
        guard let state else { return }
        guard let window = view.window ?? NSApp.keyWindow ?? NSApp.mainWindow else { return }
        let topLevel = state.root?.children?.compactMap { state.entries[$0]?.name } ?? []

        askWhereToExtract(in: window, startingIn: folderNextToTheArchive(of: state)) { [weak self] folder in
            self?.extract(into: folder, names: topLevel) {
                state.extract(to: folder, smart: Keys.smartExtractionEnabled())
            }
        }
    }

    // MARK: - Extracting

    /// Where the folder dialog opens: the archive's own folder when "Extract
    /// next to the archive" is on. The preview still asks — it may write only
    /// where it is given access — but the answer is one click away.
    private func folderNextToTheArchive(of state: ArchiveState) -> URL? {
        Keys.extractNextToArchiveEnabled() ? state.url?.deletingLastPathComponent() : nil
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
