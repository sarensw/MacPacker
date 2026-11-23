//
//  EditedElsewhereBar.swift
//  MacPacker
//
//  Says that a file saved in the editor is back as an unsaved change, and
//  offers to save it into the archive.
//

import Core
import SwiftUI

struct EditedElsewhereBar: View {
    @ObservedObject var state: ArchiveState
    /// Read so the bar names the editor anew once Settings change it.
    @AppStorage(Keys.textEditor) private var chosen: String = ""

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(.archiveEditedElsewhere(TextEditorApps.name(of: TextEditorApps.current(chosen: chosen))))
                .lineLimit(2)
            Spacer(minLength: 8)
            Button {
                state.save()
            } label: {
                Text(.commonSave)
            }
            .disabled(state.isSaving)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
