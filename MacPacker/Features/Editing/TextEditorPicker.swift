//
//  TextEditorPicker.swift
//  MacPacker
//
//  Settings › General › "Edit files with": the installed editors, CotEditor
//  to get when it is missing, and any other app.
//

import AppKit
import Core
import SwiftUI

struct TextEditorPicker: View {
    @AppStorage(Keys.textEditor) private var chosen: String = ""

    /// Entries that do something instead of being picked.
    private static let getCotEditor = "getCotEditor"
    private static let other = "other"

    var body: some View {
        let listed = TextEditors.listed(
            chosen: chosen.isEmpty ? nil : chosen,
            systemDefault: TextEditorApps.systemDefault,
            isInstalled: TextEditorApps.isInstalled)
        Picker(String(""), selection: Binding(get: { TextEditorApps.current(chosen: chosen) }, set: pick)) {
            ForEach(listed, id: \.self) { id in
                Text(verbatim: TextEditorApps.name(of: id)).tag(id)
            }
            Divider()
            if !TextEditorApps.isInstalled(TextEditors.cotEditor) {
                Text(.settingsGetCotEditor).tag(Self.getCotEditor)
            }
            Text(.settingsEditorOther).tag(Self.other)
        }
        .labelsHidden()
    }

    private func pick(_ id: String) {
        switch id {
        case Self.getCotEditor:
            NSWorkspace.shared.open(TextEditorApps.cotEditorStorePage)
        case Self.other:
            if let app = chooseApp() { chosen = app }
        default:
            chosen = id
        }
    }

    /// Any app, picked in Applications.
    private func chooseApp() -> String? {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }
}
