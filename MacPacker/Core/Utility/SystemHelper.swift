//
//  SystemHelper.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 28.07.25.
//

import AppKit
import Core

/// Sizes, dates and permissions as the app writes them everywhere. The text
/// itself comes from `EntryText` in Core, which the Quick Look preview shares
/// (#251 B11).
final class SystemHelper {
    @MainActor static let shared = SystemHelper()

    private init() {}

    func format(bytes: Int) -> String {
        EntryText.size(bytes)
    }

    /// `512000` reads "512 KB"; less than zero reads as nothing.
    func format(bytes: Int64) -> String {
        EntryText.size(bytes)
    }

    func formatDate(_ date: Date) -> String {
        EntryText.date(date)
    }

    func formatPosixPermissions(_ permissions: Int) -> String {
        EntryText.permissions(permissions)
    }
}
