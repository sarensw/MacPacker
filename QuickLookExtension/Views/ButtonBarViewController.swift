//
//  ButtonBarViewController.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 05.10.25.
//

import AppKit

protocol ButtonBarDelegate: AnyObject {
    func didRequestExtractSelected()
    func didRequestExtractAll()
}

final class ButtonBarViewController: NSViewController {
    weak var delegate: ButtonBarDelegate?
    private let stack = NSStackView()
    
    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        let extractSelectedButton = NSButton()
        extractSelectedButton.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)!
        extractSelectedButton.title = NSLocalizedString("Extract selected", comment: "Button in the tooblar that allows the user to extract the selected files.")
        extractSelectedButton.imagePosition = .imageLeading
        extractSelectedButton.bezelStyle = .accessoryBar
        extractSelectedButton.isBordered = true
        extractSelectedButton.translatesAutoresizingMaskIntoConstraints = false
        extractSelectedButton.target = self
        extractSelectedButton.action = #selector(extractSelected)
        
        let extractAllButton = NSButton()
        extractAllButton.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)!
        extractAllButton.title = NSLocalizedString("Extract archive", comment: "Button in the toolbar that allows the user to extract the full archive to a target directory.")
        extractAllButton.imagePosition = .imageLeading
        extractAllButton.bezelStyle = .accessoryBar
        extractAllButton.isBordered = true
        extractAllButton.translatesAutoresizingMaskIntoConstraints = false
        extractAllButton.target = self
        extractAllButton.action = #selector(extractAll)
        
        stack.addArrangedSubview(extractSelectedButton)
        stack.addArrangedSubview(extractAllButton)
        
        NSLayoutConstraint.activate([
            extractSelectedButton.heightAnchor.constraint(equalToConstant: 32),
            extractAllButton.heightAnchor.constraint(equalToConstant: 32),
            
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Actions
    @objc private func extractSelected() {
        delegate?.didRequestExtractSelected()
    }
    
    @objc private func extractAll() {
        delegate?.didRequestExtractAll()
    }
}
