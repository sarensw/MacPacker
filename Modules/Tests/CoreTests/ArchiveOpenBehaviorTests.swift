import Foundation
import Testing
@testable import Core

extension AllCoreTests {
    struct ArchiveOpenBehaviorTests {
        private let archive = URL(fileURLWithPath: "/tmp/test.zip")

        @Test func defaultAndUnknownSettingsBrowse() {
            let defaults = isolatedDefaults()
            #expect(ArchiveOpenBehavior.current(in: defaults) == .browse)
            defaults.set("future-value", forKey: Keys.archiveOpenBehavior)
            #expect(ArchiveOpenBehavior.current(in: defaults) == .browse)
            defaults.set(ArchiveOpenBehavior.extractImmediately.rawValue, forKey: Keys.archiveOpenBehavior)
            #expect(ArchiveOpenBehavior.current(in: defaults) == .extractImmediately)
        }

        @Test func onlyOptedInFileArchivesExtract() {
            #expect(ArchiveOpenBehavior.extractImmediately.shouldExtract(archive, isArchive: true, isDirectory: false))
            #expect(!ArchiveOpenBehavior.browse.shouldExtract(archive, isArchive: true, isDirectory: false))
            #expect(!ArchiveOpenBehavior.extractImmediately.shouldExtract(archive, isArchive: true, isDirectory: true))
            #expect(!ArchiveOpenBehavior.extractImmediately.shouldExtract(archive, isArchive: false, isDirectory: false))
            #expect(!ArchiveOpenBehavior.extractImmediately.shouldExtract(URL(string: "app.macpacker://open")!, isArchive: true, isDirectory: false))
        }

        @Test func launchWindowsRemainAvailableForExplicitLaunch() {
            #expect(!ArchiveOpenBehavior.extractImmediately.suppressesLaunchWindows(hasRequestedBrowser: true))
            #expect(ArchiveOpenBehavior.extractImmediately.suppressesLaunchWindows(hasRequestedBrowser: false))
            #expect(!ArchiveOpenBehavior.browse.suppressesLaunchWindows(hasRequestedBrowser: false))
        }
    }
}
