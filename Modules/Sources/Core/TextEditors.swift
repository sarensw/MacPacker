//
//  TextEditors.swift
//  Modules
//
//  Which app Edit hands a file to. What is installed is the app's to ask (Core
//  has no AppKit), so it comes in as a function.
//

import Foundation

public enum TextEditors {
    public static let cotEditor = "com.coteditor.CotEditor"
    /// Part of macOS: always there.
    public static let textEdit = "com.apple.TextEdit"
    /// Offered in Settings when installed, in this order.
    public static let suggested = [cotEditor, textEdit, "com.barebones.bbedit", "com.microsoft.VSCode"]

    /// The editor Edit uses: the one chosen in Settings while it is installed,
    /// else CotEditor, else TextEdit.
    public static func resolve(chosen: String?, isInstalled: (String) -> Bool) -> String {
        if let chosen, isInstalled(chosen) { return chosen }
        return isInstalled(cotEditor) ? cotEditor : textEdit
    }

    /// What Settings lists: the suggested editors that are installed, then the
    /// Mac's own app for text and the one picked with "Other…", each once.
    public static func listed(chosen: String?, systemDefault: String?, isInstalled: (String) -> Bool) -> [String] {
        var ids = suggested.filter(isInstalled)
        for id in [systemDefault, chosen].compactMap({ $0 }) where isInstalled(id) && !ids.contains(id) {
            ids.append(id)
        }
        return ids
    }
}
