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
                    ArchiveSavePanel.runAndSave(state: state, window: NSApp.keyWindow)
                } else {
                    state.save()
                }
            } label: {
                Text("Save Archive", comment: "File menu entry that saves the pending changes of the front archive window")
            }
            .keyboardShortcut("s", modifiers: [.command])

            Button {
                guard let state = Self.frontArchiveState(),
                      state.canBeEdited, !state.selectedItems.isEmpty, !state.isSaving else { return }
                state.remove(items: state.selectedItems)
            } label: {
                Text("Delete Selected", comment: "File menu entry that deletes the selected items from the front archive window")
            }
            .keyboardShortcut(.delete, modifiers: [.command])
        }
    }
}
