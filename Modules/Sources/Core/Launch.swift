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

    /// What a launch was started for.
    public enum Reason: Sendable {
        /// The app itself: the Dock, Finder, Spotlight.
        case app
        /// Launch parameters that put their own window up.
        case ownWindow
        /// Archives to open, by Open With or a double click. The first one
        /// takes the launch window.
        case archives
        /// An action from Finder's menu.
        case finderAction
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
        case .app, .archives:
            return true
        // A Finder action extracts or compresses and leaves the screen as it
        // was, or opens the one window it is about (#279).
        case .ownWindow, .finderAction:
            return false
        }
    }

    /// Nothing said what the launch was started for. Somebody still started
    /// the app, and must not be left without a window.
    /// - Returns: whether to show the launch windows now
    public mutating func waitedLongEnough() -> Bool {
        started(for: .app)
    }

    /// Whether the app checks for updates. Only an app somebody uses does. One
    /// that a Finder action started is gone a moment later: a check begun
    /// there is cut off, the updater counts it as made all the same, and what
    /// it found is shown to nobody.
    /// - Parameter usedAsApp: a window of the app has been open since the launch
    public func checksForUpdates(usedAsApp: Bool) -> Bool {
        switch reason {
        case .app, .ownWindow, .archives:
            true
        case .finderAction:
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
        reason == .finderAction && !usedAsApp && !actionUnderWay && !somethingOnScreen
    }
}
