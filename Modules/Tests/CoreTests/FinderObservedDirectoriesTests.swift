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

        @Test("Volume refresh removes stale roots after unmount or rename")
        func refresh() {
            let old = URL(fileURLWithPath: "/Volumes/Old", isDirectory: true)
            let new = URL(fileURLWithPath: "/Volumes/New", isDirectory: true)
            let before = FinderObservedDirectories.urls(homeDirectory: home, userName: "tester", mountedVolumes: [old])
            let after = FinderObservedDirectories.urls(homeDirectory: home, userName: "tester", mountedVolumes: [new])
            #expect(before.contains(old))
            #expect(after.contains(new))
            #expect(!after.contains(old))
            #expect(FinderObservedDirectories.urls(homeDirectory: home, userName: "tester", mountedVolumes: []).contains(home))
        }
    }
}
