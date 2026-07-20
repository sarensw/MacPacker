//
//  ArchiveCommands.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 16.07.26.
//

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
                Text("Save", comment: "File menu entry that saves the pending changes of the front archive window")
            }
            .keyboardShortcut("s", modifiers: [.command])

            Button {
                // Save As… always asks for a new location and writes the current
                // content (with pending edits) there; the window then tracks it.
                guard let state = Self.frontArchiveState(),
                      state.canBeEdited, state.hasPendingChanges, !state.isSaving else { return }
                ArchiveSavePanel.runAndSave(state: state, window: NSApp.keyWindow)
            } label: {
                Text("Save As…", comment: "File menu entry that saves the front archive to a new location")
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            // Deletion is the standard Edit ▸ Delete menu item, handled by the
            // archive table (ArchiveTableView.delete(_:)) — not a File command.
        }
    }
}
