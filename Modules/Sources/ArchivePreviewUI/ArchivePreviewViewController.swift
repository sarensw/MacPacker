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
    private var state: ArchiveState?

    /// The archive's security-scoped access, held for as long as the preview is
    /// on screen. Expanding a nested archive re-reads the file long after
    /// ``loadPreview(of:)`` returned, so the scope cannot end with that call.
    private var scopedURL: URL?

    /// Resumed once the host has something worth showing: the loaded archive, a
    /// failure message, or the locked-archive notice. QuickLook only puts the
    /// view on screen after `preparePreviewOfFile` returns.
    private var readyContinuation: CheckedContinuation<Void, Never>?
    /// Bumped by every load. The harness loads a second archive into the same
    /// controller, so a load can be superseded while it is still running: its
    /// callbacks must not touch the UI the newer load owns, and must not resume
    /// the newer load's continuations.
    private var loadGeneration = 0
    /// The archive being previewed, for handing it over to MacPacker.
    private var previewedURL: URL?
    /// Set once the locked-archive notice is up, so the finished load does not
    /// replace it with the engine's "could not read this" message.
    private var showsLockedNotice = false

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

    private lazy var lockedLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.alignment = .center
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }()

    /// A locked archive is handed to MacPacker rather than unlocked here: the
    /// Quick Look panel keeps key focus, so a password field in this view never
    /// receives a keystroke. Clicks do arrive, so a button works.
    private lazy var lockedNotice: NSStackView = {
        let open = NSButton(
            title: String(localized: "Open in MacPacker", bundle: .module, comment: "Button in the Quick Look preview that opens a password protected archive in the MacPacker app"),
            target: self,
            action: #selector(openInMacPacker))

        let stack = NSStackView(views: [lockedLabel, open])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isHidden = true
        return stack
    }()

    public init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        scopedURL?.stopAccessingSecurityScopedResource()
    }

    public override func loadView() {
        addChild(contentViewController)

        let container = NSView()
        let content = contentViewController.view
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        container.addSubview(messageLabel)
        container.addSubview(lockedNotice)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            messageLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            messageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),

            lockedNotice.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            lockedNotice.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            lockedNotice.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16),
            lockedNotice.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16)
        ])

        view = container
    }

    /// Loads `url` as an archive and shows its contents.
    ///
    /// Returns once the preview has something to show — the loaded archive, an
    /// error message, or the password prompt — so the host never displays an
    /// empty view, and an encrypted archive can still ask for its password.
    public func loadPreview(of url: URL) async throws {
        PreviewLog.general.info("Preview requested", context: ["file": url.lastPathComponent])

        // QuickLook hands the extension a security-scoped URL; inside the appex
        // sandbox the archive bytes are only readable while we're accessing it.
        // (The in-app harness opens a user-selected URL, which is broadly
        // accessible — that's why the harness shows content but the real
        // extension came up empty.)
        if url.startAccessingSecurityScopedResource() {
            scopedURL?.stopAccessingSecurityScopedResource()
            scopedURL = url
        }

        // Let go of whatever the previous load was waiting on before replacing
        // it: an unresumed continuation hangs its caller forever.
        readyContinuation?.resume()
        readyContinuation = nil
        hideLockedNotice()
        previewedURL = url

        loadGeneration += 1
        let generation = loadGeneration

        let state = ArchivePreviewLoader.makeState()
        state.passwordProvider = { [weak self] request in
            await self?.requestPassword(request, generation: generation) ?? nil
        }
        self.state = state

        state.open(url: url)
        let openTask = state.openTask
        Task { [weak self] in
            _ = try? await openTask?.value
            self?.finishLoad(generation: generation)
        }
        await withCheckedContinuation { continuation in
            readyContinuation = continuation
        }
    }

    /// Shows whatever the finished load produced, unless a newer load has
    /// taken over in the meantime.
    private func finishLoad(generation: Int) {
        guard generation == loadGeneration, let state else { return }
        // A locked archive ends as a failed load; its notice says more than the
        // engine's error would, so leave it standing.
        guard !showsLockedNotice else {
            signalReady()
            return
        }

        let entryCount = state.entries.count
        let rootChildren = state.root?.children?.count ?? -1
        PreviewLog.general.info("Preview load finished", context: [
            "entries": "\(entryCount)",
            "topLevelItems": "\(rootChildren)",
            "engine": state.activeEngine?.configId ?? "none",
            "error": state.error ?? "none"
        ])

        if let error = state.error {
            PreviewLog.general.error("Preview load failed", context: ["error": error])
            showMessage("Couldn’t read this archive.\n\(error)")
        } else if state.root == nil || (state.root?.children?.isEmpty ?? true) {
            // Opened without an error but produced no listable entries — surface
            // it instead of rendering a silent, empty list.
            showMessage("No entries read from this archive.\nentries: \(entryCount)")
        } else {
            hideMessage()
            contentViewController.state = state
        }

        signalReady()
    }

    // MARK: - Locked archives

    /// Reports that the archive needs a password, and offers to open it in
    /// MacPacker — this preview cannot take one.
    ///
    /// Finder's Quick Look panel keeps key focus, so a text field here never
    /// receives a keystroke; clicks do arrive, which is why a button works. The
    /// engine is answered `nil` right away rather than left waiting for an entry
    /// that can never come.
    private func requestPassword(_ request: ArchivePasswordRequest, generation: Int) async -> String? {
        guard generation == loadGeneration else { return nil }
        PreviewLog.general.info("Archive is locked, offering the hand-off", context: [
            "file": request.url.lastPathComponent,
            "attempt": "\(request.attempt)"
        ])
        showLockedNotice()
        // The notice is only on screen once the host shows the view, and it only
        // does that after `preparePreviewOfFile` returns.
        signalReady()
        return nil
    }

    private func showLockedNotice() {
        lockedLabel.stringValue = String(
            localized: "This archive is password protected.",
            bundle: .module,
            comment: "Shown in the Quick Look preview when an archive needs a password to be read")
        showsLockedNotice = true
        lockedNotice.isHidden = false
        messageLabel.isHidden = true
        contentViewController.view.isHidden = true
    }

    private func hideLockedNotice() {
        showsLockedNotice = false
        lockedNotice.isHidden = true
    }

    /// Hands the archive to MacPacker through the app's url scheme, the same way
    /// the Finder extension does, so the password can be entered there.
    @objc private func openInMacPacker() {
        guard let url = previewedURL,
              let scheme = Bundle.main.object(forInfoDictionaryKey: "MacPackerURLScheme") as? String,
              !scheme.isEmpty else {
            PreviewLog.general.error("Cannot hand over: no url scheme in the extension's Info.plist")
            return
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "files", value: url.path),
            URLQueryItem(name: "target", value: url.deletingLastPathComponent().path)
        ]
        guard let appURL = components.url else { return }

        PreviewLog.general.info("Handing the archive to MacPacker", context: ["file": url.lastPathComponent])
        if !NSWorkspace.shared.open(appURL) {
            PreviewLog.general.error("MacPacker did not open", context: ["scheme": scheme])
        }
    }

    // MARK: - Helpers

    private func signalReady() {
        readyContinuation?.resume()
        readyContinuation = nil
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
