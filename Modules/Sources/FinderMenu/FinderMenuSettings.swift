//
//  FinderMenuSettings.swift
//  Modules
//
//  Created by Stephan Arenswald on 17.08.26.
//

import Foundation

/// Which Finder menu items are shown, shared between the app (writes) and the
/// Finder extension (reads) through the app group container.
///
/// Unset keys fall back to `isEnabledByDefault` rather than being registered,
/// so a fresh extension process shows the right menu without the app ever
/// having run.
public enum FinderMenuSettings {

    /// The app group container, resolved exactly like `UserDefaults.macPackerShared`
    /// in Core — from the running target's Info.plist (`MPAppGroupIdentifier`,
    /// fed by `$(APP_GROUP_ID)`), so no team ID is baked in and the group can
    /// differ per configuration. Duplicated rather than imported: linking Core
    /// would drag 7-Zip and XADMaster into a process Finder loads, which is the
    /// whole reason this module exists.
    ///
    /// Falls back to the standard domain when there is no group — an unsigned
    /// build, or a unit-test bundle without the key — so a missing container
    /// shows the default menu instead of no menu.
    ///
    /// `nonisolated(unsafe)` because `UserDefaults` is documented as thread-safe
    /// but not marked `Sendable`.
    nonisolated(unsafe) public static let defaults: UserDefaults = {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "MPAppGroupIdentifier") as? String,
              !group.isEmpty,
              let shared = UserDefaults(suiteName: group) else {
            return .standard
        }
        return shared
    }()

    public static func key(for item: FinderMenuItem) -> String {
        "finderMenu.\(item.rawValue)"
    }

    /// Nest the items under a "MacPacker" submenu (7-Zip's "Cascaded context
    /// menu"). Off puts them straight into Finder's context menu.
    public static let cascadedKey = "finderMenu.cascaded"

    public static func isEnabled(_ item: FinderMenuItem, in defaults: UserDefaults = defaults) -> Bool {
        defaults.object(forKey: key(for: item)) as? Bool ?? item.isEnabledByDefault
    }

    public static func isCascaded(in defaults: UserDefaults = defaults) -> Bool {
        defaults.object(forKey: cascadedKey) as? Bool ?? true
    }

    /// The items to build a menu from, in catalog order, filtered by what the
    /// user enabled and by what the selection holds.
    public static func visibleItems(
        files: Int,
        folders: Int,
        in defaults: UserDefaults = defaults
    ) -> [FinderMenuItem] {
        FinderMenuItem.allCases.filter { item in
            isEnabled(item, in: defaults) && item.applies(toFiles: files, folders: folders)
        }
    }
}
