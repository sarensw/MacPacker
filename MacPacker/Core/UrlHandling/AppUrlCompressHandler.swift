//
//  AppUrlCompressHandler.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 16.07.26.
//

import AppKit
import Core
import FinderMenu
import Foundation
import Swift7zip
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "url")

/// Writes `items` into a new archive at `destination` through the same
/// add/save path the UI uses; the format follows the destination's extension.
/// - Returns: whether the archive was written.
@MainActor
private func writeArchive(
    _ items: [URL],
    to destination: URL,
    catalog: ArchiveTypeCatalog,
    engineSelector: ArchiveEngineSelectorProtocol,
    options: CompressionOptions? = nil
) async -> Bool {
    log.notice("Compressing \(items.count) item(s) to \(destination.lastPathComponent)")
    let state = ArchiveState(catalog: catalog, engineSelector: engineSelector)
    await state.compress(items, to: destination, options: options)

    if let error = state.error {
        log.error("Compress failed", context: ["error": error])
        return false
    }
    log.notice("Compress done", context: ["file": destination.lastPathComponent])
    return true
}

/// Finder compression actions: writes next to the selected files, asking for
/// or generating a password only for the two encrypted 7z actions.
class AppUrlCompressHandler: AppUrlHandler {
    private let catalog: ArchiveTypeCatalog
    private let engineSelector: ArchiveEngineSelectorProtocol

    init(catalog: ArchiveTypeCatalog, engineSelector: ArchiveEngineSelectorProtocol) {
        self.catalog = catalog
        self.engineSelector = engineSelector
    }

    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) {
        log.notice("Compress handler: \(appUrl.files.count) file(s)", context: ["target": appUrl.target.path])

        // access to the folder covers reading the inputs and writing the archive
        Task { @MainActor in
            guard await FolderAccessStore.shared.ensureAccess(forFolder: appUrl.target) else {
                log.error("No access to \(appUrl.target.lastPathComponent) — cannot compress")
                return
            }
            let password: String?
            switch appUrl.action {
            case .compress:
                password = nil
            case .compressWithPassword:
                NSApp.activate(ignoringOtherApps: true)
                guard let entered = FinderPasswordPrompt.ask() else { return }
                password = entered
            case .encryptWithNewPassword:
                NSApp.activate(ignoringOtherApps: true)
                guard let generated = FinderPasswordPrompt.generateAndCopy() else { return }
                password = generated
            default:
                return
            }
            // A password action always writes 7z, even if an untrusted app URL
            // supplies a different format. The password never travels in it.
            let ext = password == nil ? appUrl.format ?? "zip" : "7z"
            let name = appUrl.archiveName(
                CompressDestination.name(files: appUrl.files, target: appUrl.target, ext: ext),
                extension: ext
            )
            let dest = CompressDestination.unique(named: name, in: appUrl.target)
            let options = password.map(FinderArchivePassword.compressionOptions(password:))
            if await writeArchive(appUrl.files, to: dest, catalog: self.catalog,
                                  engineSelector: self.engineSelector, options: options) {
                NSWorkspace.shared.activateFileViewerSelecting([dest])
            }
        }
    }
}

@MainActor
private enum FinderPasswordPrompt {
    static func ask() -> String? {
        var previousPassword = ""
        var previousConfirmation = ""
        var problem: String?
        while true {
            let alert = NSAlert()
            alert.messageText = String(localized: "Compress with Password…", comment: "Finder action and setting to ask for a password and create an encrypted 7z archive")
            alert.informativeText = problem ?? String(localized: "Create an encrypted 7z archive with hidden file names.", comment: "Explains the Finder password compression dialog")
            let password = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
            password.placeholderString = String(localized: .commonPassword)
            password.stringValue = previousPassword
            let confirmation = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
            confirmation.placeholderString = String(localized: .archiveSavePasswordVerify)
            confirmation.stringValue = previousConfirmation
            let fields = NSStackView(views: [password, confirmation])
            fields.orientation = .vertical
            fields.spacing = 8
            for field in [password, confirmation] {
                field.widthAnchor.constraint(equalToConstant: 320).isActive = true
                field.heightAnchor.constraint(equalToConstant: 24).isActive = true
            }
            fields.setFrameSize(NSSize(width: 320, height: 56))
            alert.accessoryView = fields
            alert.addButton(withTitle: String(localized: "Compress", comment: "Confirm button in the Finder password compression dialog"))
            alert.addButton(withTitle: String(localized: .commonCancel))
            alert.window.initialFirstResponder = password
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            previousPassword = password.stringValue
            previousConfirmation = confirmation.stringValue
            if previousPassword.isEmpty {
                problem = String(localized: "Enter a password before compressing.", comment: "Validation in the Finder password compression dialog")
            } else if previousPassword != previousConfirmation {
                problem = String(localized: .errorPasswordMismatch)
            } else {
                return previousPassword
            }
        }
    }

    static func generateAndCopy() -> String? {
        let password: String
        do {
            password = try FinderArchivePassword.generate()
        } catch {
            NSAlert(error: error).runModal()
            return nil
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Encrypt with a New Password…", comment: "Finder action and setting to generate and copy a password for a new encrypted 7z archive")
        alert.informativeText = String(localized: "Save this password. MacPacker will copy it before creating the encrypted 7z archive, and you will need it to extract the files.", comment: "Warns the user to retain the generated archive password")
        let field = NSTextField(string: password)
        field.isEditable = false
        field.isSelectable = true
        field.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        field.setFrameSize(NSSize(width: 350, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Copy Password & Compress", comment: "Confirm button for generated-password Finder compression"))
        alert.addButton(withTitle: String(localized: .commonCancel))
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(password, forType: .string) else {
            let failure = NSAlert()
            failure.messageText = String(localized: "Could not copy the password", comment: "Error before generating an encrypted archive from Finder")
            failure.informativeText = String(localized: "No archive was created. Try again so you can keep the password.", comment: "Explains why generated-password compression was stopped")
            failure.runModal()
            return nil
        }
        return password
    }
}

/// Finder action "Compress Each Item Separately": one zip per selected item,
/// each next to its source. One folder grant covers them all.
class AppUrlCompressEachHandler: AppUrlHandler {
    private let catalog: ArchiveTypeCatalog
    private let engineSelector: ArchiveEngineSelectorProtocol

    init(catalog: ArchiveTypeCatalog, engineSelector: ArchiveEngineSelectorProtocol) {
        self.catalog = catalog
        self.engineSelector = engineSelector
    }

    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) {
        log.notice("Compress-each handler: \(appUrl.files.count) item(s)")

        Task { @MainActor in
            guard await FolderAccessStore.shared.ensureAccess(forFolder: appUrl.target) else {
                log.error("No access to \(appUrl.target.lastPathComponent) — cannot compress")
                return
            }
            var written: [URL] = []
            for item in appUrl.files {
                let dest = CompressDestination.unique(
                    named: CompressDestination.name(files: [item], target: appUrl.target),
                    in: appUrl.target
                )
                if await writeArchive([item], to: dest, catalog: self.catalog, engineSelector: self.engineSelector) {
                    written.append(dest)
                }
            }
            if !written.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(written)
            }
        }
    }
}

/// Finder action "Compress Contents of "<folder>"": zips what is inside the
/// folder, without the folder itself, as `<folder>.zip` next to it. The grant
/// on the surrounding folder covers reading the contents too.
class AppUrlCompressContentsHandler: AppUrlHandler {
    private let catalog: ArchiveTypeCatalog
    private let engineSelector: ArchiveEngineSelectorProtocol

    init(catalog: ArchiveTypeCatalog, engineSelector: ArchiveEngineSelectorProtocol) {
        self.catalog = catalog
        self.engineSelector = engineSelector
    }

    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) {
        guard let folder = appUrl.files.first else { return }
        log.notice("Compress-contents handler", context: ["folder": folder.lastPathComponent])

        Task { @MainActor in
            guard await FolderAccessStore.shared.ensureAccess(forFolder: appUrl.target) else {
                log.error("No access to \(appUrl.target.lastPathComponent) — cannot compress")
                return
            }
            let contents: [URL]
            do {
                // the stored grant found above gives access only inside its scope (#278)
                contents = try Sandbox.accessSync(url: folder) {
                    try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                }
            } catch {
                log.error("Could not list the folder", context: ["error": error.localizedDescription])
                return
            }
            guard !contents.isEmpty else {
                log.notice("Folder is empty — nothing to compress")
                return
            }
            let dest = CompressDestination.unique(
                named: CompressDestination.name(files: [folder], target: appUrl.target),
                in: appUrl.target
            )
            if await writeArchive(contents, to: dest, catalog: self.catalog, engineSelector: self.engineSelector) {
                NSWorkspace.shared.activateFileViewerSelecting([dest])
            }
        }
    }
}

/// Finder action "Add to Archive…": opens a new-archive window pre-filled
/// with the selection; the user picks name/format/level on save.
class AppUrlAddToArchiveHandler: AppUrlHandler {

    func handle(appUrl: AppUrl, archiveWindowManager: ArchiveWindowManager) {
        log.notice("Add-to-archive handler: \(appUrl.files.count) file(s)")

        // the selected files live in the target folder — one folder grant
        // makes them readable for the later save
        Task { @MainActor in
            guard await FolderAccessStore.shared.ensureAccess(forFolder: appUrl.target) else {
                log.error("No access to \(appUrl.target.lastPathComponent) — cannot add to archive")
                return
            }
            archiveWindowManager.openCreateArchiveWindow(with: appUrl.files)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
