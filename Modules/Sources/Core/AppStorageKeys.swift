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
    public static let showColumnCompressedSize = "showColumnCompressedSize"
    public static let showColumnUncompressedSize = "showColumnUncompressedSize"
    public static let showColumnModificationDate = "showColumnModificationDate"
    public static let showColumnPosixPermissions = "showColumnPosixPermissions"
    
    public static let defaultOrderColumn = "defaultOrderColum"
    public static let defaultOrderColumnAscending = "defaultOrderColumnAscending"

    // window settings
    public static let toolbarDisplayMode = "toolbarDisplayMode"

    // register defaults upon app start so that the archive table has a default it
    // can use when showing the table for the first time
    public static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            defaultOrderColumn: ArchiveSortOrder.name.rawValue,
            defaultOrderColumnAscending: true,
        ])
    }
}
