//
//  ContentView.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 05.10.25.
//

import AppKit
import os

final class ContentViewController: NSViewController, ButtonBarDelegate {
    var archive: Archive? {
        didSet {
            archiveViewController.archive = archive
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
        guard let archive else { return }
        guard let selectedItems = archiveViewController.selectedItems else { return }
        guard let window = view.window ?? NSApp.keyWindow ?? NSApp.mainWindow else { return }
        
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        
        let handler = XadMasterHandler()
        
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK, let url = panel.url {
                do {
                    try handler.extract(
                        archive: archive,
                        items: selectedItems,
                        to: url.path
                    )
                } catch {
                    
                }
            }
        }
        
        panel.beginSheetModal(for: window, completionHandler: completion)
    }
    
    func didRequestExtractAll() {
        guard let archive else { return }
        guard let window = view.window ?? NSApp.keyWindow ?? NSApp.mainWindow else { return }
        
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        
        let handler = XadMasterHandler()
        
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK, let url = panel.url {
                do {
                    try handler.extractAll(
                        archive: archive,
                        to: url.path
                    )
                } catch {
                    
                }
            }
        }
        
        panel.beginSheetModal(for: window, completionHandler: completion)
    }
}
