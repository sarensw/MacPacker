//
//  FinderServices.swift
//  Modules
//

import AppKit

/// MacPacker's entries in Finder's Services menu.
///
/// Finder asks no Finder Sync extension for a menu on what sits in iCloud
/// Drive, OneDrive, Dropbox or any other File Provider folder, so MacPacker's
/// Finder menu is missing there. The Services menu is not (#342). Each
/// service turns the selection into the request its Finder menu entry sends,
/// and the app carries it out the same way.
///
/// `NSServices` in Info.plist names these methods by their `NSMessage`:
/// renaming one breaks its service. It also sets
/// `NSShouldActivateForServiceRequest` to false where the Finder menu entry
/// leaves Finder in front: AppKit reads that key, Apple does not document it,
/// and without it AppKit brings the app to the front for every service.
@MainActor
public final class FinderServices: NSObject {
    private let perform: @MainActor ([AppUrl]) -> Void

    /// - Parameter perform: carries out a service's requests, as the app
    ///   carries out the Finder extension's
    public init(perform: @escaping @MainActor ([AppUrl]) -> Void) {
        self.perform = perform
    }

    /// Extract Here: each archive next to itself.
    @objc public func extract(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        perform(AppUrl.extractHere(Self.selection(on: pasteboard)))
    }

    /// Compress to "<name>.zip", next to the selection.
    @objc public func compress(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        perform(Self.request(.compress, for: Self.selection(on: pasteboard)))
    }

    /// Add to Archive…: a new archive window holding the selection, which
    /// takes more files.
    @objc public func createArchive(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        perform(Self.request(.addToArchive, for: Self.selection(on: pasteboard)))
    }

    private static func selection(on pasteboard: NSPasteboard) -> [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    /// The Finder extension sends the folder Finder shows as the target. A
    /// service gets the selection only: its first item's folder is the one
    /// shown, unless Finder shows search results.
    private static func request(_ action: AppUrlAction, for selection: [URL]) -> [AppUrl] {
        guard let folder = selection.first?.deletingLastPathComponent() else { return [] }
        return [AppUrl(action: action, files: selection, target: folder)]
    }
}

// MARK: - On or off, and where to switch them (#412)

extension FinderServices {
    /// Whether Finder shows at least one of `services` in its context menu.
    ///
    /// macOS keeps each user's choice in the `NSServicesStatus` preference of
    /// `pbs`, under "<bundle id> - <menu title> - <message>", where System
    /// Settings writes `enabled_context_menu`. A service nobody switched has
    /// no entry: it shows when it names a required context, as ours all do.
    /// - Parameters:
    ///   - services: `NSServices` as Info.plist declares them
    ///   - status: `pbs`'s `NSServicesStatus`
    public static func isOn(_ services: [[String: Any]], bundleIdentifier: String, status: [String: Any]) -> Bool {
        services.contains { service in
            guard let message = service["NSMessage"] as? String,
                  let title = (service["NSMenuItem"] as? [String: Any])?["default"] as? String else { return false }
            let choice = status["\(bundleIdentifier) - \(title) - \(message)"] as? [String: Any]
            if let shown = choice?["enabled_context_menu"] as? NSNumber { return shown.boolValue }
            return service["NSRequiredContext"] != nil
        }
    }

    /// Whether Finder shows this app's services now. The sandbox lets the app
    /// read `pbs`'s preferences; writing them would take a temporary exception,
    /// so the switches stay in System Settings.
    public static var isOn: Bool {
        // Picks up what System Settings changed since the last read.
        CFPreferencesAppSynchronize("pbs" as CFString)
        let status = CFPreferencesCopyAppValue("NSServicesStatus" as CFString, "pbs" as CFString) as? [String: Any] ?? [:]
        let services = Bundle.main.object(forInfoDictionaryKey: "NSServices") as? [[String: Any]] ?? []
        return isOn(services, bundleIdentifier: Bundle.main.bundleIdentifier ?? "", status: status)
    }

    /// Opens System Settings at Keyboard ▸ Keyboard Shortcuts ▸ Services, where
    /// the user turns the services on and off.
    ///
    /// macOS 27 has a link for it, macOS 14 to 26 have none: there it takes
    /// what AppKit's own "Services Settings…" menu item sends on macOS 15, the
    /// Keyboard pane with a request to reveal its Services section, which 27
    /// ignores. Neither is documented; should one stop working, System
    /// Settings still opens on Keyboard. Both measured sandboxed, without any
    /// entitlement, on 14.8.7, 15.7.7, 26.6.2 and 27.2.
    public static func openSettings() {
        if #available(macOS 27, *) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Services")!)
            return
        }
        let reveal = ["tabID": "hotkeysTabIdentifier", "revealElementKey": "section.services"]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: reveal, format: .xml, options: 0) else { return }
        // Deprecated, but its replacement, open(_:withApplicationAt:configuration:),
        // reaches the Keyboard pane only: the request does not get through.
        _ = NSWorkspace.shared.open(
            [URL(fileURLWithPath: "/System/Library/PreferencePanes/Keyboard.prefPane")],
            withAppBundleIdentifier: "com.apple.systempreferences",
            options: .default,
            additionalEventParamDescriptor: NSAppleEventDescriptor(descriptorType: 0x7074_7275 /* 'ptru' */, data: data),
            launchIdentifiers: nil
        )
    }
}
