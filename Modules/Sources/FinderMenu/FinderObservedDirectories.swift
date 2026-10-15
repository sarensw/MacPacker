import AppKit

/// Finder asks for context menus only underneath these roots. Watching a root
/// does not grant the app permission to read or write its files.
///
/// Finder also draws the app's icon on every root it shows in its sidebar. The
/// app's Info.plist names the `externaldrive` symbol (`CFBundleSymbolName` in
/// `CFBundlePrimaryIcon`), which Finder draws instead, so drives keep looking
/// like drives (#345).
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

    /// The volumes Finder shows. Leaves out the system, recovery and simulator
    /// volumes a Mac has mounted all the time.
    public static func visibleVolumes() -> [URL] {
        FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
    }

    /// Hands over the roots when it is created, and again each time a volume is
    /// mounted or ejected, for as long as it is kept alive. Finder needs each
    /// mounted volume's root, not just its /Volumes parent.
    ///
    /// A rename is not watched on purpose. Finder keeps following a volume it
    /// was given through a rename by itself, and at the moment the rename is
    /// announced the system still lists the volume under its old name. Handing
    /// that list over made Finder drop a volume that was renamed back to the
    /// name it had before.
    ///
    /// `onChange` runs on the thread that posts the notification, which for
    /// `NSWorkspace` is the main thread.
    public final class Watcher: NSObject {
        private let homeDirectory: URL
        private let userName: String
        private let notificationCenter: NotificationCenter
        private let mountedVolumes: () -> [URL]
        private let onChange: (Set<URL>) -> Void

        public init(
            homeDirectory: URL,
            userName: String,
            notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
            mountedVolumes: @escaping () -> [URL] = FinderObservedDirectories.visibleVolumes,
            onChange: @escaping (Set<URL>) -> Void
        ) {
            self.homeDirectory = homeDirectory
            self.userName = userName
            self.notificationCenter = notificationCenter
            self.mountedVolumes = mountedVolumes
            self.onChange = onChange
            super.init()

            for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
                notificationCenter.addObserver(self, selector: #selector(volumesDidChange(_:)), name: name, object: nil)
            }
            report()
        }

        deinit {
            notificationCenter.removeObserver(self)
        }

        @objc private func volumesDidChange(_ notification: Notification) {
            report()
        }

        private func report() {
            onChange(FinderObservedDirectories.urls(
                homeDirectory: homeDirectory, userName: userName, mountedVolumes: mountedVolumes()))
        }
    }
}
