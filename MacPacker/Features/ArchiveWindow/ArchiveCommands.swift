//
//  ArchiveCommands.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 16.07.26.
//

import Core
import SwiftUI

/// The archive state of the key window, published by `ContentView` so the
/// main-menu commands can act on whatever window is in front.
struct FocusedArchiveStateKey: FocusedValueKey {
    typealias Value = ArchiveState
}

extension FocusedValues {
    var archiveState: ArchiveState? {
        get { self[FocusedArchiveStateKey.self] }
        set { self[FocusedArchiveStateKey.self] = newValue }
    }
}

/// File-menu commands for editing the front archive (7-Zip parity: the
/// toolbar actions are reachable from the menu bar and by shortcut too).
struct ArchiveCommands: Commands {
    @FocusedValue(\.archiveState) private var archiveState

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Divider()

            Button {
                guard let archiveState else { return }
                if archiveState.url == nil {
                    ArchiveSavePanel.runAndSave(state: archiveState, window: NSApp.keyWindow)
                } else {
                    archiveState.save()
                }
            } label: {
                Text("Save Archive", comment: "File menu entry that saves the pending changes of the front archive window")
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(archiveState == nil || archiveState?.canBeEdited != true || archiveState?.hasPendingChanges != true)

            Button {
                guard let archiveState else { return }
                archiveState.remove(items: archiveState.selectedItems)
            } label: {
                Text("Delete Selected", comment: "File menu entry that deletes the selected items from the front archive window")
            }
            .keyboardShortcut(.delete, modifiers: [.command])
            .disabled(archiveState == nil || archiveState?.canBeEdited != true || archiveState?.selectedItems.isEmpty != false)
        }
    }
}
