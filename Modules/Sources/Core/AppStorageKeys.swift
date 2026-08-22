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
    /// Not exposed anywhere yet — every drop uses the default. The writer reads
    /// it, so it is ready for whenever the window grows its options back.
    public static let dropWindowLevel = "dropWindowLevel"
    // Default *values*, not key names: `@AppStorage` needs a compile-time default
    // and `CompressSettings.current` needs the same fallback when it reads
    // UserDefaults directly, so both read these and cannot disagree.
    public static let defaultDropWindowFormat = "zip"
    public static let defaultDropWindowLevel = 5

    // register defaults upon app start so that the archive table has a default it
    // can use when showing the table for the first time
    public static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            defaultOrderColumn: ArchiveSortOrder.name.rawValue,
            defaultOrderColumnAscending: true,
            dropWindowFloats: true,
        ])
    }
}
