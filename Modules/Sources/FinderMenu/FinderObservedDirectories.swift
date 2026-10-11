import Foundation

/// Finder asks for context menus only underneath these roots. Watching a root
/// does not grant the app permission to read or write its files.
public enum FinderObservedDirectories {
    public static func urls(homeDirectory: URL, userName: String, mountedVolumes: [URL]) -> Set<URL> {
        var roots: Set<URL> = [
            URL(fileURLWithPath: homeDirectory.path, isDirectory: true),
            URL(fileURLWithPath: "/Users/\(userName)", isDirectory: true)
        ]
        for volume in mountedVolumes where volume.isFileURL {
            let root = URL(fileURLWithPath: volume.standardizedFileURL.path, isDirectory: true)
            // Registering / would include system directories and every user's
            // home. Retain the existing home scope on the startup volume.
            if root.path != "/" { roots.insert(root) }
        }
        return roots
    }
}
