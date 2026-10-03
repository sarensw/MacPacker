//
//  ArchiveSharePresenter.swift
//  MacPacker
//
//  A finished archive is handed to the system's sharing services. Finder can
//  launch the app without a window, so that path supplies its own small anchor.
//

import AppKit

@MainActor
final class ArchiveSharePresenter: NSObject, @preconcurrency NSSharingServicePickerDelegate, NSSharingServiceDelegate, NSWindowDelegate {
    static let shared = ArchiveSharePresenter()

    private var archive: URL?
    private var picker: NSSharingServicePicker?
    private var chosenService: NSSharingService?
    private var panel: NSPanel?
    private var shareButton: NSButton?

    func present(_ url: URL, from view: NSView? = nil) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        dismiss()
        archive = url

        if let view, view.window != nil {
            showPicker(relativeTo: view)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 112),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = String(localized: "Share Archive…", comment: "Title of the small window used to share a newly compressed archive")
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let label = NSTextField(labelWithString: url.lastPathComponent)
        label.lineBreakMode = .byTruncatingMiddle
        label.alignment = .center
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let button = NSButton(
            title: String(localized: "Share…", comment: "Button that opens macOS sharing services for the finished archive"),
            target: self, action: #selector(shareClicked(_:)))
        button.bezelStyle = .rounded
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 112))
        let stack = NSStackView(views: [label, button])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
        ])
        panel.contentView = content
        panel.minSize = NSSize(width: 360, height: 112)
        panel.setContentSize(NSSize(width: 360, height: 112))
        self.panel = panel
        shareButton = button
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // The window remains usable if AppKit declines to open a picker outside
        // a mouse event; clicking Share then opens the same native picker.
        DispatchQueue.main.async { [weak self, weak button] in
            guard let self, let button, self.shareButton === button else { return }
            self.showPicker(relativeTo: button)
        }
    }

    @objc private func shareClicked(_ sender: NSButton) {
        showPicker(relativeTo: sender)
    }

    private func showPicker(relativeTo view: NSView) {
        guard let archive else { return }
        let picker = NSSharingServicePicker(items: [archive])
        picker.delegate = self
        self.picker = picker
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                              delegateFor sharingService: NSSharingService) -> (any NSSharingServiceDelegate)? {
        guard sharingServicePicker === picker else { return nil }
        chosenService = sharingService
        return self
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                              didChoose sharingService: NSSharingService?) {
        guard sharingServicePicker === picker else { return }
        if let sharingService {
            chosenService = sharingService
        } else {
            dismiss()
        }
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        guard sharingService === chosenService else { return }
        dismiss()
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
        guard sharingService === chosenService else { return }
        if let panel {
            NSAlert(error: error).beginSheetModal(for: panel)
        } else {
            NSApp.presentError(error)
        }
    }

    func windowWillClose(_ notification: Notification) {
        picker?.delegate = nil
        picker?.close()
        picker = nil
        chosenService = nil
        panel = nil
        shareButton = nil
        archive = nil
    }

    private func dismiss() {
        picker?.delegate = nil
        picker?.close()
        picker = nil
        chosenService = nil
        let panel = panel
        self.panel = nil
        shareButton = nil
        archive = nil
        panel?.delegate = nil
        panel?.close()
    }
}
