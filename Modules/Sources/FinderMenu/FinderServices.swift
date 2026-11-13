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
