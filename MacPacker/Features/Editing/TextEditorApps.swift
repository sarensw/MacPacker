//
//  TextEditorApps.swift
//  MacPacker
//
//  "Edit with …": which editors are installed and what they are called, asked
//  of Launch Services. Which one is used is `TextEditors`' to say.
//

import AppKit
import Core
import tb
import UniformTypeIdentifiers

private let log = tb.Logger(subsystem: "app.MacPacker", category: "edit")

enum TextEditorApps {
    static func isInstalled(_ id: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
    }

    /// The Mac's own app for plain text.
    static var systemDefault: String? {
        NSWorkspace.shared.urlForApplication(toOpen: .plainText).flatMap { Bundle(url: $0)?.bundleIdentifier }
    }

    /// The editor "Edit with …" uses, for what Settings say.
    static func current(chosen: String?) -> String {
        TextEditors.resolve(chosen: chosen?.isEmpty == false ? chosen : nil, isInstalled: isInstalled)
    }

    static var current: String {
        current(chosen: UserDefaults.standard.string(forKey: Keys.textEditor))
    }

    /// The app's name as Finder shows it.
    static func name(of id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            // only CotEditor is offered without being installed
            return id == TextEditors.cotEditor ? "CotEditor" : id
        }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// Hands `file` to the editor in use. The system gives that app access to
    /// this one file; its saves land in it, where `takeBackEdits` finds them.
    static func open(_ file: URL) {
        let id = current
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        log.info("Handing a copy to the editor", context: ["editor": id])
        NSWorkspace.shared.open([file], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                log.error("Editor did not open the copy", context: ["editor": id, "error": "\(error)"])
            }
        }
    }

    static let cotEditorStorePage = URL(string: "macappstore://apps.apple.com/app/id1024640650")!
}
