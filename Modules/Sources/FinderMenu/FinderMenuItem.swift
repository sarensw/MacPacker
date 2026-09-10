//
//  FinderMenuItem.swift
//  Modules
//
//  Created by Stephan Arenswald on 17.08.26.
//

import Foundation

/// One entry of the Finder context menu.
///
/// The Finder extension builds its menu from these, the app's settings shows a
/// checkbox per case. Both sides need the list and the on/off state, but the
/// extension must stay free of `Core` (which pulls 7-Zip and XADMaster into a
/// process Finder loads), hence this dependency-free module.
///
/// Titles are deliberately *not* here: the menu says `Extract to "Photos"`
/// while the settings row says `Extract to folder`, so each target localizes
/// its own wording in its own string catalog.
///
/// Case order is menu order. Raw values are the settings keys — never rename
/// a case.
public enum FinderMenuItem: String, CaseIterable, Sendable {
    /// Open the selection in an archive window.
    case open
    /// Extract next to the archive.
    case extractHere
    /// Extract into a new folder named after the archive — one per archive
    /// when several are selected.
    case extractToFolder
    /// Ask where to extract, then extract there.
    case extractToChosenFolder
    /// New-archive window, pre-filled with the selection.
    case addToArchive
    /// Straight to `<name>.zip`, no questions.
    case compressToZip
    /// `<name> 2026-09-10 14.30.zip` — a quick snapshot before an edit.
    case compressToDatedZip
    /// Straight to `<name>.7z`, no questions.
    case compressTo7z
    /// One zip per selected item.
    case compressEachSeparately
    /// A zip of what is inside a folder, without the folder itself.
    case compressFolderContents

    /// A lean default: extracting in place or to a chosen folder, and zip —
    /// plain and dated. Everything else is opt-in, the way 7-Zip and NanaZip
    /// let users grow their menu.
    public var isEnabledByDefault: Bool {
        switch self {
        case .extractHere, .extractToChosenFolder, .compressToZip, .compressToDatedZip:
            true
        case .open, .extractToFolder, .addToArchive, .compressTo7z,
             .compressEachSeparately, .compressFolderContents:
            false
        }
    }

    /// Whether the entry can act on a selection of `files` files and
    /// `folders` folders.
    public func applies(toFiles files: Int, folders: Int) -> Bool {
        switch self {
        case .open, .extractHere, .extractToFolder, .extractToChosenFolder:
            // archives are files; extracting a folder is meaningless
            files > 0
        case .compressEachSeparately:
            // with a single item this is just "Compress to"
            files + folders > 1
        case .compressFolderContents:
            files == 0 && folders == 1
        case .addToArchive, .compressToZip, .compressToDatedZip, .compressTo7z:
            true
        }
    }

    /// What this item asks the main app to do.
    public var action: AppUrlAction {
        switch self {
        case .open: .open
        case .extractHere: .extractHere
        case .extractToFolder: .extractToFolder
        case .extractToChosenFolder: .extractTo
        case .addToArchive: .addToArchive
        case .compressToZip, .compressToDatedZip, .compressTo7z: .compress
        case .compressEachSeparately: .compressEach
        case .compressFolderContents: .compressContents
        }
    }

    /// Extension of the archive the item produces, `nil` when it does not
    /// produce one directly. The writer picks the format from it.
    public var archiveExtension: String? {
        switch self {
        case .compressToZip, .compressToDatedZip, .compressEachSeparately, .compressFolderContents: "zip"
        case .compressTo7z: "7z"
        case .open, .extractHere, .extractToFolder, .extractToChosenFolder, .addToArchive: nil
        }
    }

    /// Whether `value` is an extension one of the entries produces — the
    /// allowlist for the `format` the app takes from its url scheme, which any
    /// app or web page can call and which ends up in a file name.
    public static func isArchiveExtension(_ value: String) -> Bool {
        allCases.contains { $0.archiveExtension == value }
    }

    /// Whether the archive's name carries the date and time of compressing.
    public var isDated: Bool {
        self == .compressToDatedZip
    }

    /// `photos.zip` → `photos 2026-09-10 14.30.zip`. Sorts by date in Finder
    /// and stays a valid file name — no `:` or `/`, whatever the locale.
    public static func datedName(
        _ name: String,
        extension ext: String,
        at date: Date,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        let suffix = "." + ext
        let stem = name.hasSuffix(suffix) ? String(name.dropLast(suffix.count)) : name
        return "\(stem) \(formatter.string(from: date))\(suffix)"
    }
}
