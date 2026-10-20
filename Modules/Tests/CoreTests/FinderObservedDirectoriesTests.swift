//
//  FinderObservedDirectoriesTests.swift
//  Modules
//
//  Finder shows MacPacker's menu only below the roots the extension hands it.
//  Two things decide them: which roots a set of volumes turns into, and when
//  the extension looks again. The second part runs against a real disk image
//  too, because what the system lists at the moment a volume is mounted,
//  renamed or ejected is exactly what a fake volume list cannot tell.
//

import AppKit
import Foundation
import Testing
import FinderMenu

extension AllCoreTests {
    struct FinderObservedDirectoriesTests {
        private let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

        @Test("Finder watches mounted volumes as well as the home folder")
        func externalVolumes() {
            let external = URL(fileURLWithPath: "/Volumes/External Drive", isDirectory: true)
            let roots = FinderObservedDirectories.urls(homeDirectory: home, userName: "tester", mountedVolumes: [external])
            #expect(roots.contains(external))
            #expect(roots.contains(home))
        }

        @Test("Sandbox home keeps the real home fallback")
        func sandboxHome() {
            let sandbox = URL(fileURLWithPath: "/Users/tester/Library/Containers/app/Data", isDirectory: true)
            let roots = FinderObservedDirectories.urls(homeDirectory: sandbox, userName: "tester", mountedVolumes: [])
            #expect(roots == [sandbox, home])
        }

        @Test("Mounted roots are normalized and non-file URLs are ignored")
        func normalizedRoots() {
            let volume = URL(fileURLWithPath: "/Volumes/External Drive", isDirectory: true)
            let roots = FinderObservedDirectories.urls(homeDirectory: home, userName: "tester", mountedVolumes: [
                URL(fileURLWithPath: "/Volumes/External Drive/./"), volume,
                URL(string: "https://example.com/volume")!
            ])
            #expect(roots == [home, volume])
        }

        @Test("Finder does not watch the entire startup volume")
        func excludesStartupRoot() {
            let roots = FinderObservedDirectories.urls(homeDirectory: home, userName: "tester", mountedVolumes: [URL(fileURLWithPath: "/")])
            #expect(!roots.contains(URL(fileURLWithPath: "/")))
        }

        // MARK: - When the roots are handed over

        /// A watcher on a notification center of its own, with a volume list
        /// the test edits, recording every set of roots it hands over.
        private final class Fixture {
            let center = NotificationCenter()
            var volumes: [URL]
            private(set) var reports: [Set<URL>] = []
            private var watcher: FinderObservedDirectories.Watcher?

            init(volumes: [URL] = []) {
                self.volumes = volumes
                watcher = FinderObservedDirectories.Watcher(
                    homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true),
                    userName: "tester",
                    notificationCenter: center,
                    mountedVolumes: { [unowned self] in self.volumes },
                    onChange: { [unowned self] in self.reports.append($0) }
                )
            }
        }

        private let drive = URL(fileURLWithPath: "/Volumes/Drive", isDirectory: true)

        @Test("The roots are handed over once when the watcher starts")
        func reportsAtStart() {
            let fixture = Fixture(volumes: [drive])
            #expect(fixture.reports == [[home, drive]])
        }

        @Test("A mounted volume is added")
        func mountAddsTheVolume() {
            let fixture = Fixture()
            fixture.volumes = [drive]
            fixture.center.post(name: NSWorkspace.didMountNotification, object: nil)
            #expect(fixture.reports == [[home], [home, drive]])
        }

        @Test("An ejected volume is removed")
        func ejectRemovesTheVolume() {
            let fixture = Fixture(volumes: [drive])
            fixture.volumes = []
            fixture.center.post(name: NSWorkspace.didUnmountNotification, object: nil)
            #expect(fixture.reports == [[home, drive], [home]])
        }

        /// Seen in a VM: the system still listed the volume when its unmount
        /// was announced, so it was never taken out, and Finder, which drops
        /// the root by itself, lost the menu on it once it was mounted again.
        @Test("An ejected volume is removed even while the system still lists it")
        func ejectWhileStillListed() {
            let fixture = Fixture(volumes: [drive])
            fixture.center.post(
                name: NSWorkspace.didUnmountNotification, object: nil,
                userInfo: [NSWorkspace.volumeURLUserInfoKey: URL(fileURLWithPath: "/Volumes/Drive/")]
            )
            #expect(fixture.reports == [[home, drive], [home]])
        }

        /// Finder follows a renamed volume by itself. Looking again here read
        /// the old name, and handing that over lost the menu on a volume that
        /// was renamed back.
        @Test("A rename hands nothing over")
        func renameHandsNothingOver() {
            let fixture = Fixture(volumes: [drive])
            fixture.center.post(name: NSWorkspace.didRenameVolumeNotification, object: nil)
            #expect(fixture.reports.count == 1)
        }

        @Test("Hidden system volumes stay out")
        func hiddenVolumesStayOut() {
            let visible = FinderObservedDirectories.visibleVolumes().map(\.path)
            let hidden = visible.filter { $0.hasPrefix("/System/Volumes/") }
            #expect(visible.contains("/"))
            #expect(hidden.isEmpty)
        }

        // MARK: - A real volume

        private final class RenameCounter: NSObject {
            var count = 0
            @objc func renamed(_ notification: Notification) { count += 1 }
        }

        /// Polls on the main actor, which lets the run loop deliver the
        /// workspace notifications in between.
        @MainActor
        private func eventually(_ condition: () -> Bool) async throws -> Bool {
            for _ in 0..<300 {
                if condition() { return true }
                try await Task.sleep(for: .milliseconds(100))
            }
            return condition()
        }

        /// Runs a tool off the main actor. The extension's main thread is idle
        /// when a volume changes, so it hears about it at once; a test that
        /// blocked the main thread on the tool would hear about it only after
        /// the system had caught up, and miss what the extension sees.
        @concurrent
        @discardableResult
        private func tool(_ path: String, _ arguments: [String]) async throws -> String {
            try run(path, arguments)
        }

        /// Mounts a disk image the way a drive is plugged in, and watches it
        /// with the notification center and the volume list the extension uses.
        @Test("A real volume is added on mount, kept through a rename and back, removed on eject")
        @MainActor
        func realVolume() async throws {
            let id = UUID().uuidString.prefix(8)
            let name = "MacPackerTest-\(id)"
            let mount = URL(fileURLWithPath: "/Volumes/\(name)", isDirectory: true)
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FinderObservedDirectoriesTests-\(id)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let image = folder.appendingPathComponent("volume.dmg").path
            try await tool("/usr/bin/hdiutil", ["create", "-size", "2m", "-fs", "HFS+", "-volname", name, image])

            var device: String?
            defer {
                // a failed expectation must not leave the volume mounted
                if let device {
                    let eject = try? Process.run(URL(fileURLWithPath: "/usr/bin/hdiutil"), arguments: ["detach", device, "-force", "-quiet"])
                    eject?.waitUntilExit()
                }
                try? FileManager.default.removeItem(at: folder)
            }

            var reports: [Set<URL>] = []
            let watcher = FinderObservedDirectories.Watcher(homeDirectory: home, userName: "tester") { reports.append($0) }
            let renames = RenameCounter()
            let workspace = NSWorkspace.shared.notificationCenter
            workspace.addObserver(renames, selector: #selector(RenameCounter.renamed(_:)), name: NSWorkspace.didRenameVolumeNotification, object: nil)
            defer { workspace.removeObserver(renames) }
            #expect(reports.last?.contains(mount) == false)

            // the line that names the mount point starts with the volume's device
            let attached = try await tool("/usr/bin/hdiutil", ["attach", "-noautoopen", image])
            for line in attached.split(separator: "\n") where line.contains(mount.path) {
                device = line.split(separator: " ").first.map { String($0).trimmingCharacters(in: .whitespaces) }
            }
            let slice = try #require(device, "no device in: \(attached)")
            let mounted = try await eventually { reports.last?.contains(mount) == true }
            #expect(mounted, "mounted volume was not handed over")

            try await tool("/usr/sbin/diskutil", ["rename", slice, "\(name)-2"])
            try await tool("/usr/sbin/diskutil", ["rename", slice, name])
            let announced = try await eventually { renames.count >= 2 }
            #expect(announced, "the renames were not announced")
            #expect(reports.last?.contains(mount) == true, "the roots no longer cover the volume after it was renamed back")

            try await tool("/usr/bin/hdiutil", ["detach", slice, "-force"])
            device = nil
            let ejected = try await eventually { reports.last?.contains(mount) == false }
            #expect(ejected, "ejected volume is still handed over")
            withExtendedLifetime(watcher) {}
        }
    }
}
