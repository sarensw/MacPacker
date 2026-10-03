import AppKit
import Combine
import Core
import Foundation

/// Serializes file-open extractions so multiple selected archives do not stack
/// password/access panels. Each archive extracts next to itself, including when
/// one open event contains files from different folders.
@MainActor
final class ArchiveOpenExtractor {
    private let catalog: ArchiveTypeCatalog
    private let engineSelector: ArchiveEngineSelectorProtocol
    private let didFinish: () -> Void
    private var queued: [URL] = []
    private var active: URL?
    private(set) var isBusy = false

    init(catalog: ArchiveTypeCatalog, engineSelector: ArchiveEngineSelectorProtocol, didFinish: @escaping () -> Void) {
        self.catalog = catalog
        self.engineSelector = engineSelector
        self.didFinish = didFinish
    }

    func enqueue(_ url: URL) {
        let url = url.standardizedFileURL
        guard active != url, !queued.contains(url) else { return }
        queued.append(url)
        guard !isBusy else { return }
        isBusy = true
        Task {
            while !queued.isEmpty {
                let next = queued.removeFirst()
                active = next
                await extract(next)
            }
            active = nil
            isBusy = false
            didFinish()
        }
    }

    private func extract(_ url: URL) async {
        let destination = url.deletingLastPathComponent()
        guard await FolderAccessStore.shared.ensureAccess(forFolder: destination) else { return }
        let prompt = ArchiveOpenPasswordPrompt()
        let state = ArchiveState(catalog: catalog, engineSelector: engineSelector)
        state.passwordProvider = { await prompt.request($0) }
        state.folderAccessProvider = { await FolderAccessStore.shared.ensureAccess(forFileIn: $0) }
        state.open(url: url)
        do {
            try await state.openTask?.value
        } catch {
            if !prompt.wasCancelled { showOpenError(error.localizedDescription) }
            return
        }
        // ArchiveState records opening failures instead of rethrowing them.
        if prompt.wasCancelled { return }
        if let error = state.openError {
            showOpenError(error)
            return
        }
        guard state.root != nil else { return }

        state.extract(to: destination, smart: Keys.smartExtractionEnabled())
        for await busy in state.$isBusy.values where !busy { break }
        // The existing progress controller shows extraction failures and closes
        // after success. Do not show a browser just to host that progress.
    }

    private func showOpenError(_ reason: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: .errorOpenArchive)
        alert.informativeText = reason
        alert.addButton(withTitle: String(localized: .commonOk))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
