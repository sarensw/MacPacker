//
//  ArchiveCommands.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 16.07.26.
//

import Combine
import Core
import SwiftUI

/// File-menu commands for editing the front archive (7-Zip parity: the
/// toolbar actions are reachable from the menu bar and by shortcut too).
///
/// The archive windows are plain NSWindows hosting SwiftUI content — no
/// SwiftUI scene — so `@FocusedValue` never reaches these commands. The
/// front window's state is resolved through its window controller instead,
/// and the actions validate themselves (no-op when nothing applies).
struct ArchiveCommands: Commands {

    @MainActor
    private static func frontArchiveState() -> ArchiveState? {
        let controller = NSApp.keyWindow?.windowController as? ArchiveWindowController
            ?? NSApp.mainWindow?.windowController as? ArchiveWindowController
        return controller?.archiveState
    }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Divider()

            FilenameEncodingMenu()

            Divider()

            Button {
                guard let state = Self.frontArchiveState(),
                      state.canBeEdited, state.hasPendingChanges, !state.isSaving else { return }
                if state.url == nil {
                    // never saved — Save behaves like Save As (asks for a location)
                    ArchiveSavePanel.runAndSave(state: state, window: NSApp.keyWindow)
                } else {
                    state.save()
                }
            } label: {
                Text(.commonSave)
            }
            .keyboardShortcut("s", modifiers: [.command])

            Button {
                // Save As… always asks for a new location and writes the current
                // content (with any pending edits) there; the window then tracks
                // it. Works on a clean archive too — then it just saves a copy.
                guard let state = Self.frontArchiveState(),
                      state.canBeEdited, !state.isSaving else { return }
                ArchiveSavePanel.runAndSave(state: state, window: NSApp.keyWindow)
            } label: {
                Text(.commonSaveAs)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            // Deletion is the standard Edit ▸ Delete menu item, handled by the
            // archive table (ArchiveTableView.delete(_:)) — not a File command.
        }

        // Edit ▸ Find, right after Select All, as in Finder and Mail.
        CommandGroup(after: .pasteboard) {
            Divider()

            Button {
                // `.searchable` is backed by the standard search toolbar item,
                // which knows how to expand itself and take the focus
                let window = NSApp.keyWindow ?? NSApp.mainWindow
                window?.toolbar?.items
                    .lazy
                    .compactMap { $0 as? NSSearchToolbarItem }
                    .first?
                    .beginSearchInteraction()
            } label: {
                Label(
                    String(localized: .commonFind),
                    systemImage: "magnifyingglass"
                )
            }
            .keyboardShortcut("f", modifiers: [.command])
        }
    }
}

/// File ▸ Filename Encoding: what to read the names of the archive in front in,
/// for when they come out garbled. It sits here and not in the window because
/// hardly anyone needs it, and only for an archive that does not say what its
/// names are in. A menu stays where it is; a control in the window would come and go.
private struct FilenameEncodingMenu: View {
    @StateObject private var front = FrontArchiveNames()

    private static let encodings = ArchiveNameEncoding.allCases.sorted {
        $0.localizedName.localizedStandardCompare($1.localizedName) == .orderedAscending
    }

    var body: some View {
        Menu {
            Picker(selection: Binding(
                get: { front.chosen },
                set: { front.read(as: $0) }
            )) {
                Text(.archiveFilenameEncodingDetectAutomatically).tag(ArchiveNameEncoding?.none)
                Divider()
                ForEach(Self.encodings) { encoding in
                    Text(verbatim: encoding.localizedName).tag(ArchiveNameEncoding?.some(encoding))
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            Text(.archiveFilenameEncoding)
        }
        .disabled(!front.canChoose)
    }
}

/// What the menu needs of the archive in front, and no more: following all of
/// `ArchiveState` would rebuild the menu with every tick of a progress.
///
/// A window that is not an archive window leaves nothing to choose.
@MainActor
private final class FrontArchiveNames: ObservableObject {
    @Published private(set) var chosen: ArchiveNameEncoding?
    @Published private(set) var canChoose = false

    private var state: ArchiveState?
    private var windows: AnyCancellable?
    private var names: AnyCancellable?

    init() {
        let center = NotificationCenter.default
        windows = center.publisher(for: NSWindow.didBecomeMainNotification)
            .map { ($0.object as? NSWindow)?.windowController as? ArchiveWindowController }
            .merge(with: center.publisher(for: NSWindow.didResignMainNotification).map { _ in nil })
            .sink { [weak self] controller in self?.follow(controller?.archiveState) }
        // The first window can be up before the menu is.
        follow((NSApp?.mainWindow?.windowController as? ArchiveWindowController)?.archiveState)
    }

    func read(as encoding: ArchiveNameEncoding?) {
        state?.readNames(as: encoding)
    }

    private func follow(_ state: ArchiveState?) {
        self.state = state
        chosen = nil
        canChoose = false
        names = state.map { state in
            state.$nameEncoding
                .combineLatest(state.$chosenNameEncoding, state.$diff, state.$isBusy)
                .sink { [weak self] encoding, chosen, diff, isBusy in
                    self?.chosen = chosen
                    self?.canChoose = encoding != nil && diff.isEmpty && !isBusy
                }
        }
    }
}
