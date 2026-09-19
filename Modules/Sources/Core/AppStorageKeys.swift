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
    /// Whether opened archives are remembered for the start page's Recent list
    /// (and the Dock's Recent Documents menu). On by default; turning it off also
    /// empties what was already collected — a history you can no longer see is one
    /// you should no longer keep.
    public static let rememberRecentArchives = "rememberRecentArchives"
    
    // table settings
    public static let showParentRow = "showParentRow"
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
    /// Leave `.DS_Store` files out of what Quick Compress writes.
    public static let dropWindowExcludeDSStore = "dropWindowExcludeDSStore"

    // save panel
    /// The format the save panel opened on last. 7-Zip opens on the last one too.
    public static let saveOptionsFormat = "saveOptionsFormat"
    /// One format's remembered save settings, JSON.
    public static func saveOptionsSettings(_ format: String) -> String { "saveOptionsSettings.\(format)" }
    /// Leave `.DS_Store` files out of archives. Off by default, as in Finder's
    /// own Compress.
    public static let saveOptionsExcludeDSStore = "saveOptionsExcludeDSStore"

    // register defaults upon app start so that the archive table has a default it
    // can use when showing the table for the first time
    public static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            defaultOrderColumn: ArchiveSortOrder.name.rawValue,
            defaultOrderColumnAscending: true,
            dropWindowFloats: true,
            rememberRecentArchives: true,
        ])
    }
}
