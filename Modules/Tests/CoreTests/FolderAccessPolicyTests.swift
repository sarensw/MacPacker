//
//  FolderAccessPolicyTests.swift
//  Modules
//
//  `FolderAccess` — which folder a grant has to cover, and whether one is
//  needed at all. Paths only: nothing is read, nothing is prompted, so the
//  decision the app acts on is testable without a sandbox.
//

import Testing
import Foundation
@testable import Core

extension AllCoreTests {
    struct FolderAccessPolicyTests {

        private let downloads = URL(fileURLWithPath: "/Users/tester/Downloads", isDirectory: true)

        private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

        /// A folder grant is a directory url — what `folder(for:)` hands back.
        private func dir(_ path: String) -> URL { URL(fileURLWithPath: path, isDirectory: true) }

        // MARK: - The folder a grant has to cover

        @Test func aFileNeedsItsContainingFolder() {
            #expect(FolderAccess.folder(for: url("/Users/tester/Work/a.zip"), isDirectory: false)
                    == dir("/Users/tester/Work"))
        }

        @Test func aFolderNeedsItself() {
            #expect(FolderAccess.folder(for: url("/Users/tester/Work"), isDirectory: true)
                    == dir("/Users/tester/Work"))
        }

        // MARK: - Containment

        @Test func insideCountsTheFolderItself() {
            #expect(FolderAccess.isInside(downloads, downloads))
            #expect(FolderAccess.isInside(url("/Users/tester/Downloads/tools/x.zip"), downloads))
        }

        /// A name that merely starts with the same characters is a different folder.
        @Test func aPrefixIsNotInside() {
            #expect(!FolderAccess.isInside(url("/Users/tester/DownloadsOld/x.zip"), downloads))
        }

        // MARK: - Decision

        @Test func aGrantOnTheFolderCoversIt() {
            let decision = FolderAccess.decide(
                for: url("/Users/tester/Work/a.zip"), isDirectory: false,
                downloads: downloads,
                isCovered: { $0 == self.dir("/Users/tester/Work") })
            #expect(decision == .covered)
        }

        /// The recents list bookmarks each archive *file*. That grant reads the
        /// file and nothing else — writing next to it, or reading a sibling
        /// volume, still needs the folder. So a file-level grant must not pass
        /// for one.
        @Test func aGrantOnTheFileAloneDoesNotCoverTheFolder() {
            let archive = url("/Users/tester/Work/a.zip")
            let decision = FolderAccess.decide(
                for: archive, isDirectory: false,
                downloads: downloads,
                isCovered: { $0 == archive })
            #expect(decision == .prompt(dir("/Users/tester/Work")))
        }

        @Test func downloadsIsCoveredByTheEntitlement() {
            let decision = FolderAccess.decide(
                for: url("/Users/tester/Downloads/tools/a.zip"), isDirectory: false,
                downloads: downloads,
                isCovered: { _ in false })
            #expect(decision == .downloads(downloads))
        }

        /// A stored grant wins over the entitlement: it needs no system prompt at all.
        @Test func aStoredGrantWinsOverDownloads() {
            let decision = FolderAccess.decide(
                for: url("/Users/tester/Downloads/a.zip"), isDirectory: false,
                downloads: downloads,
                isCovered: { _ in true })
            #expect(decision == .covered)
        }

        @Test func anythingElseIsAsked() {
            let decision = FolderAccess.decide(
                for: url("/Volumes/Backup/2026/a.zip"), isDirectory: false,
                downloads: downloads,
                isCovered: { _ in false })
            #expect(decision == .prompt(dir("/Volumes/Backup/2026")))
        }

        /// No home to speak of (a test rig, a system account): ask.
        @Test func withoutADownloadsFolderItIsAsked() {
            let decision = FolderAccess.decide(
                for: url("/Users/tester/Downloads/a.zip"), isDirectory: false,
                downloads: nil,
                isCovered: { _ in false })
            #expect(decision == .prompt(dir("/Users/tester/Downloads")))
        }
    }
}
