//
//  ArchivePreviewViewController.swift
//  ArchivePreviewUI
//

import AppKit
import Core

/// The shared, hostable archive preview UI (an expandable outline view of the
/// archive's contents plus an extract toolbar).
///
/// Both the QuickLook extension's `QLPreviewingController` shell and the in-app
/// DEBUG harness embed this controller and call ``loadPreview(of:)`` — so the
/// exact same code path can be exercised with a debugger attached by just
/// running the main app.
public final class ArchivePreviewViewController: NSViewController {
    private let contentViewController = ContentViewController()

    private lazy var messageLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.isHidden = true
        return label
    }()

    public init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        addChild(contentViewController)

        let container = NSView()
        let content = contentViewController.view
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        container.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            messageLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            messageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16)
        ])

        view = container
    }

    /// Loads `url` as an archive and shows its contents.
    ///
    /// Awaits the full load (`ArchiveState.openTask`) before returning so the
    /// host presents a finished preview instead of an empty view that fills in
    /// later. Setting `contentViewController.state` drives the outline view
    /// reload through the existing `didSet` chain.
    public func loadPreview(of url: URL) async throws {
        PreviewLog.general.debug("Previewing file at \(url.path)")

        // QuickLook hands the extension a security-scoped URL; inside the appex
        // sandbox the archive bytes are only readable while we're accessing it.
        // (The in-app harness opens a user-selected URL, which is broadly
        // accessible — that's why the harness shows content but the real
        // extension came up empty.) Access is held across the awaited load below.
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        let state = ArchivePreviewLoader.makeState()
        state.open(url: url)
        try await state.openTask?.value

        // Diagnostics: NSLog always surfaces in Console/Xcode (the appex doesn't
        // call tb.start(), so tb logs don't reach the unified log).
        let entryCount = state.entries.count
        let rootChildren = state.root?.children?.count ?? -1
        NSLog("[MacPacker QL] loadPreview path=%@ access=%d error=%@ entries=%d rootChildren=%d",
              url.path, didAccess ? 1 : 0, state.error ?? "nil", entryCount, rootChildren)

        if let error = state.error {
            PreviewLog.general.error("Preview load failed", context: ["error": error])
            showMessage("Couldn’t read this archive.\n\(error)")
            return
        }

        if state.root == nil || (state.root?.children?.isEmpty ?? true) {
            // Opened without an error but produced no listable entries — surface
            // it instead of rendering a silent, empty list.
            showMessage("No entries read from this archive.\nentries: \(entryCount) · file access: \(didAccess ? "granted" : "not security-scoped")")
            return
        }

        hideMessage()
        contentViewController.state = state
    }

    private func showMessage(_ text: String) {
        messageLabel.stringValue = text
        messageLabel.isHidden = false
        contentViewController.view.isHidden = true   // ensure the message isn't hidden behind the (opaque) outline view
    }

    private func hideMessage() {
        messageLabel.isHidden = true
        contentViewController.view.isHidden = false
    }
}
