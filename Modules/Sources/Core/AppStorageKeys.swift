//
//  AppStorageKeys.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 16.09.25.
//

import Foundation

public enum Keys {
    // general settings
    public static let settingBreadcrumbPosition = "settingBreadcrumbPosition"
    public static let quitOnLastWindowClosed = "quitOnLastWindowClosed"
    /// Whether archives open as tabs of the front window. On by default.
    public static let openArchivesInTabs = "openArchivesInTabs"
    /// Whether opened archives are remembered for the start page's Recent list
    /// (and the Dock's Recent Documents menu). On by default; turning it off also
    /// empties what was already collected — a history you can no longer see is one
    /// you should no longer keep.
    public static let rememberRecentArchives = "rememberRecentArchives"
    /// Whether extraction decides on its own that the result needs a container
    /// folder named after the archive. On by default.
    public static let smartExtraction = "smartExtraction"

    /// `smartExtraction`, read from the app group so the Quick Look extension —
    /// a separate process with its own `.standard` — sees what the app wrote.
    ///
    /// Unset falls back to `true` rather than being registered, so a fresh
    /// extension process extracts the same way without the app ever having run.
    public static func smartExtractionEnabled(in defaults: UserDefaults = .macPackerShared) -> Bool {
        defaults.object(forKey: smartExtraction) as? Bool ?? true
    }
    
    /// Whether an archive opened from Finder — a double click, Open With — is
    /// extracted next to itself, as Extract Here does, instead of opened in a
    /// window (#280). Off by default.
    public static let extractOnOpen = "extractOnOpen"

    // table settings
    public static let showParentRow = "showParentRow"
    /// Whether the archive window and Quick Look list the files Finder hides,
    /// greyed out as Finder shows them. Off by default (#304).
    public static let showHiddenFiles = "showHiddenFiles"

    /// `showHiddenFiles`, read from the app group so the Quick Look extension
    /// sees what the app wrote. Unset is off.
    public static func showHiddenFilesEnabled(in defaults: UserDefaults = .macPackerShared) -> Bool {
        defaults.bool(forKey: showHiddenFiles)
    }

    public static let showColumnCompressedSize = "showColumnCompressedSize"
    public static let showColumnUncompressedSize = "showColumnUncompressedSize"
    public static let showColumnModificationDate = "showColumnModificationDate"
    public static let showColumnPosixPermissions = "showColumnPosixPermissions"
    
    public static let defaultOrderColumn = "defaultOrderColum"
    public static let defaultOrderColumnAscending = "defaultOrderColumnAscending"

    // window settings
    public static let toolbarDisplayMode = "toolbarDisplayMode"

    // drop window
    /// Menu bar icon, off by default — an icon nobody asked for is one menu bar
    /// icon too many.
    public static let showMenuBarItem = "showMenuBarItem"
    /// Keep the drop window above other apps. On by default — a window you drag
    /// onto from Finder is useless the moment Finder covers it.
    public static let dropWindowFloats = "dropWindowFloats"
    /// Whether the quick-compress window shows its options section. Collapsed by
    /// default: the window exists to be dropped on, not configured.
    public static let dropWindowOptionsExpanded = "dropWindowOptionsExpanded"
    public static let dropWindowFormat = "dropWindowFormat"
    /// The one level Quick Compress kept for every format before it remembered
    /// its settings per format. Read to carry that choice over.
    public static let dropWindowLevel = "dropWindowLevel"
    /// Quick Compress's remembered settings for one format, JSON — kept apart
    /// from the save panel's.
    public static func dropWindowSettings(_ format: String) -> String { "dropWindowSettings.\(format)" }
    /// Quick Compress's own `.DS_Store` switch before `excludeMacData`. Read
    /// to carry that choice over.
    public static let dropWindowExcludeDSStore = "dropWindowExcludeDSStore"

    // save panel
    /// The format the save panel opened on last. 7-Zip opens on the last one too.
    public static let saveOptionsFormat = "saveOptionsFormat"
    /// One format's remembered save settings, JSON.
    public static func saveOptionsSettings(_ format: String) -> String { "saveOptionsSettings.\(format)" }
    /// The save panel's own `.DS_Store` switch before `excludeMacData`. Read
    /// to carry that choice over.
    public static let saveOptionsExcludeDSStore = "saveOptionsExcludeDSStore"

    // compressing
    /// Leave Mac-specific data out of what MacPacker compresses: `.DS_Store`
    /// files, `._` sidecars, tags, custom icons, hidden flags (#236). One switch
    /// for the save panel, Quick Compress, the start page and Finder alike. Off
    /// by default, as in Finder's own Compress.
    public static let excludeMacData = "excludeMacData"

    /// Turns `excludeMacData` on for whoever had either `.DS_Store` switch it
    /// replaces on. Only while it has no value of its own: that is the user's.
    public static func carryOverExcludeDSStore(in defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: excludeMacData) == nil,
              defaults.bool(forKey: saveOptionsExcludeDSStore) || defaults.bool(forKey: dropWindowExcludeDSStore)
        else { return }
        defaults.set(true, forKey: excludeMacData)
    }

    // register defaults upon app start so that the archive table has a default it
    // can use when showing the table for the first time
    public static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            defaultOrderColumn: ArchiveSortOrder.name.rawValue,
            defaultOrderColumnAscending: true,
            dropWindowFloats: true,
            rememberRecentArchives: true,
            openArchivesInTabs: true,
        ])
    }
}
