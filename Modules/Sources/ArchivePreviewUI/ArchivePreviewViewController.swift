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
    /// failure message, or the password prompt. QuickLook only puts the view on
    /// screen after `preparePreviewOfFile` returns, so waiting for the whole load
    /// would leave the user staring at nothing while we wait for their password.
    private var readyContinuation: CheckedContinuation<Void, Never>?
    private var passwordContinuation: CheckedContinuation<String?, Never>?
    /// What to go back to once a password has been entered.
    private var showedContentBeforePrompt = false

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

    private lazy var passwordLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.alignment = .center
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }()

    private lazy var passwordField: NSSecureTextField = {
        let field = NSSecureTextField()
        field.target = self
        field.action = #selector(submitPassword)
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    /// Inline rather than a sheet: an appex has no window of its own to attach a
    /// sheet to, and the QuickLook panel is not ours to put one on.
    private lazy var passwordPrompt: NSStackView = {
        let unlock = NSButton(
            title: String(localized: "Unlock", comment: "Button that submits the password for an encrypted archive in the Quick Look preview"),
            target: self,
            action: #selector(submitPassword))
        unlock.keyEquivalent = "\r"

        let stack = NSStackView(views: [passwordLabel, passwordField, unlock])
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
        container.addSubview(passwordPrompt)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            messageLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            messageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),

            passwordPrompt.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            passwordPrompt.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            passwordPrompt.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16),
            passwordPrompt.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),
            passwordField.widthAnchor.constraint(equalToConstant: 220)
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

        let state = ArchivePreviewLoader.makeState()
        state.passwordProvider = { [weak self] request in
            await self?.requestPassword(request) ?? nil
        }
        self.state = state

        state.open(url: url)
        let openTask = state.openTask
        Task { [weak self] in
            _ = try? await openTask?.value
            self?.finishLoad()
        }
        await withCheckedContinuation { continuation in
            readyContinuation = continuation
        }
    }

    /// Shows whatever the finished load produced.
    private func finishLoad() {
        guard let state else { return }
        hidePasswordPrompt()

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

    // MARK: - Password

    /// Asks the user for the archive's password, inline in the preview.
    private func requestPassword(_ request: ArchivePasswordRequest) async -> String? {
        PreviewLog.general.info("Password requested", context: [
            "file": request.url.lastPathComponent,
            "attempt": "\(request.attempt)"
        ])
        showPasswordPrompt(retry: request.attempt > 1)
        // The prompt is only usable once the host shows the view, and it only
        // does that after `preparePreviewOfFile` returns.
        signalReady()

        return await withCheckedContinuation { continuation in
            passwordContinuation = continuation
        }
    }

    private func showPasswordPrompt(retry: Bool) {
        // A password is asked for twice: for the archive itself (nothing on
        // screen yet) and for a nested one (the tree is showing, and goes back
        // up once the password is in).
        showedContentBeforePrompt = !contentViewController.view.isHidden
        passwordLabel.stringValue = retry
            ? String(localized: "Wrong password. Try again.", comment: "Shown in the Quick Look preview when the entered archive password did not work")
            : String(localized: "This archive is password protected.", comment: "Shown in the Quick Look preview when an archive needs a password to be read")
        passwordField.stringValue = ""
        passwordPrompt.isHidden = false
        messageLabel.isHidden = true
        contentViewController.view.isHidden = true
        view.window?.makeFirstResponder(passwordField)
    }

    private func hidePasswordPrompt() {
        passwordPrompt.isHidden = true
        passwordField.stringValue = ""
    }

    /// An empty password is a "no thanks" — the engine reports the archive as
    /// locked instead of retrying forever.
    @objc private func submitPassword() {
        guard let continuation = passwordContinuation else { return }
        passwordContinuation = nil
        let password = passwordField.stringValue
        hidePasswordPrompt()
        if showedContentBeforePrompt {
            hideMessage()   // back to the tree; the nested row keeps spinning
        } else {
            showMessage(String(localized: "Opening…", comment: "Shown in the Quick Look preview while the archive is being read"))
        }
        continuation.resume(returning: password.isEmpty ? nil : password)
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
