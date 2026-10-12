//
//  Launch.swift
//  Modules
//
//  Created by Claude on 12.10.26.
//

import Foundation

/// What the app was launched for. It decides whether the launch shows the
/// windows it shows unasked — the empty launch window and, when it is due, the
/// welcome window — and whether the app quits again once its work is done.
///
/// Decided once, by the first reason known. That is not always known when the
/// app has finished launching: AppKit hands a url over only after it is done
/// restoring windows, which is before `applicationDidFinishLaunching` on one
/// launch and after it on the next. The app therefore tells this type as soon
/// as it knows, and shows nothing before.
public struct Launch: Sendable {

    /// What started a launch.
    public enum Reason: Sendable {
        /// The app was opened as such: the Dock, Finder, Spotlight.
        case app
        /// Launch parameters that say what to show: `-ArchivePath`,
        /// `-NewArchive`, `-DropWindow` and the like.
        case launchParameters
        /// Something to open was handed over: Open With, a double click, a
        /// drop on the Dock icon, `open` in Terminal. The first archive
        /// takes the launch window.
        case openWith
        /// A request from the Finder extension, for an entry of its menu.
        case finderExtension
    }

    /// What the launch was started for, once that is known.
    public private(set) var reason: Reason?

    public init() {}

    /// The launch was started for `reason`. Only the first reason counts: what
    /// arrives later finds the app running.
    /// - Returns: whether to show the launch windows now
    public mutating func started(for reason: Reason) -> Bool {
        guard self.reason == nil else { return false }
        self.reason = reason
        switch reason {
        case .app, .openWith:
            return true
        // A Finder action extracts or compresses and leaves the screen as it
        // was, or opens the one window it is about (#279).
        case .launchParameters, .finderExtension:
            return false
        }
    }

    /// Whether the app checks for updates. Only an app somebody uses does. One
    /// that a Finder action started is gone a moment later: a check begun
    /// there is cut off, the updater counts it as made all the same, and what
    /// it found is shown to nobody.
    /// - Parameter usedAsApp: a window of the app has been open since the launch
    public func checksForUpdates(usedAsApp: Bool) -> Bool {
        switch reason {
        case .app, .launchParameters, .openWith:
            true
        case .finderExtension:
            usedAsApp
        // not known yet: the url of a Finder action can still be on its way
        case nil:
            false
        }
    }

    /// Whether the app has done what it was launched for, and quits.
    ///
    /// A Finder action that had to start the app leaves nothing behind when it
    /// is done, the Dock icon included. Not so once the app has been used as
    /// an app: then it stays, like one the user opened.
    /// - Parameters:
    ///   - usedAsApp: a window of the app has been open since the launch
    ///   - actionUnderWay: a Finder action still has work to do
    ///   - somethingOnScreen: a window is up, or about to be: progress, an
    ///     error, a question
    public func isOver(usedAsApp: Bool, actionUnderWay: Bool, somethingOnScreen: Bool) -> Bool {
        reason == .finderExtension && !usedAsApp && !actionUnderWay && !somethingOnScreen
    }
}
