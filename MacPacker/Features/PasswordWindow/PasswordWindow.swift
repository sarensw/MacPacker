//
//  PasswordWindow.swift
//  MacPacker
//
//  Asks for an archive's password where no archive window is there to hold
//  the password sheet: Finder's extract actions, and archives extracted on
//  open (#280). The same `PasswordView` as the sheet, in a window of its own.
//

import AppKit
import Core
import SwiftUI

@MainActor
enum PasswordWindow {
    /// Shows the prompt and waits for it to be answered: the password, or
    /// `nil` when it was cancelled.
    static func ask(_ request: ArchivePasswordRequest) async -> String? {
        // No close button: the window answers through its buttons only, so
        // the extraction waiting on it can never be left hanging.
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        let password = await withCheckedContinuation { continuation in
            // Return in the field and a click on OK can both arrive
            var answered = false
            let answer = { (password: String?) in
                guard !answered else { return }
                answered = true
                continuation.resume(returning: password)
            }
            window.contentViewController = NSHostingController(rootView: PasswordView(
                request: request,
                onSubmit: { answer($0) },
                onCancel: { answer(nil) }
            ).frame(width: 366))
            window.title = Constants.appName
            window.isReleasedWhenClosed = false
            // above Finder, like the folder-access prompt: it has to be answered
            window.level = .floating
            window.center()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        window.close()
        return password
    }
}
