import Foundation

/// Finder/open-with requests can extract directly. Explicit browsing inside
/// MacPacker continues to open an archive window regardless of this setting.
public enum ArchiveOpenBehavior: String, CaseIterable, Sendable {
    case browse
    case extractImmediately

    /// Missing or unrecognized stored values preserve the existing browsing behavior.
    public static func current(in defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: Keys.archiveOpenBehavior).flatMap(Self.init(rawValue:)) ?? .browse
    }

    /// Directories, unsupported files, and explicit app-URL actions keep their
    /// existing routes, even when direct extraction is selected.
    public func shouldExtract(_ url: URL, isArchive: Bool, isDirectory: Bool) -> Bool {
        self == .extractImmediately && url.isFileURL && isArchive && !isDirectory
    }

    /// File-open events may arrive after startup. In extraction mode, the
    /// untitled-document event explicitly requests the normal app window.
    public func suppressesLaunchWindows(hasRequestedBrowser: Bool) -> Bool {
        self == .extractImmediately && !hasRequestedBrowser
    }
}
