//
//  CompressDestinationTests.swift
//  Modules
//
//  `CompressDestination` — the naming and collision rules a compress action
//  applies before it writes anything. Names are computed from paths only, so
//  most cases need no files on disk; the collision test does, and gets a real
//  temporary folder.
//

import Testing
import Foundation
@testable import Core

extension AllCoreTests {
    struct CompressDestinationTests {

        private func urls(_ paths: String...) -> [URL] {
            paths.map { URL(fileURLWithPath: $0) }
        }

        // MARK: - Name

        @Test func singleFileUsesItsOwnStem() {
            let name = CompressDestination.name(
                files: urls("/tmp/work/report.pdf"),
                target: URL(fileURLWithPath: "/tmp/work"))
            #expect(name == "report.zip")
        }

        /// A folder has no extension to strip — its whole name is the stem.
        @Test func singleFolderKeepsItsName() {
            let name = CompressDestination.name(
                files: urls("/tmp/work/Photos"),
                target: URL(fileURLWithPath: "/tmp/work"))
            #expect(name == "Photos.zip")
        }

        /// Only the last extension goes: "notes.tar.gz" → "notes.tar.zip", which
        /// is what Finder's own compress does too.
        @Test func onlyTheLastExtensionIsStripped() {
            let name = CompressDestination.name(
                files: urls("/tmp/work/notes.tar.gz"),
                target: URL(fileURLWithPath: "/tmp/work"))
            #expect(name == "notes.tar.zip")
        }

        @Test func severalFilesUseTheEnclosingFolder() {
            let name = CompressDestination.name(
                files: urls("/tmp/work/a.txt", "/tmp/work/b.txt"),
                target: URL(fileURLWithPath: "/tmp/work"))
            #expect(name == "work.zip")
        }

        /// The drop window picks the format, so the extension is a parameter —
        /// a 7z drop must not produce a ".zip" name.
        @Test func extensionFollowsTheChosenFormat() {
            let files = urls("/tmp/work/report.pdf")
            let target = URL(fileURLWithPath: "/tmp/work")
            #expect(CompressDestination.name(files: files, target: target, ext: "7z") == "report.7z")
            #expect(CompressDestination.name(files: urls("/tmp/work/a.txt", "/tmp/work/b.txt"),
                                             target: target, ext: "7z") == "work.7z")
        }

        @Test func emptySelectionFallsBackToTheFolder() {
            let name = CompressDestination.name(
                files: [], target: URL(fileURLWithPath: "/tmp/work"))
            #expect(name == "work.zip")
        }

        // MARK: - Unique

        @Test func uniqueCountsUpPastExistingFiles() throws {
            let dir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("CompressDestinationTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }

            // nothing there yet — the plain name wins
            #expect(CompressDestination.unique(named: "x.zip", in: dir).lastPathComponent == "x.zip")

            try Data().write(to: dir.appendingPathComponent("x.zip"))
            #expect(CompressDestination.unique(named: "x.zip", in: dir).lastPathComponent == "x 2.zip")

            try Data().write(to: dir.appendingPathComponent("x 2.zip"))
            #expect(CompressDestination.unique(named: "x.zip", in: dir).lastPathComponent == "x 3.zip")
        }

        /// The counter goes before the extension, not after it — "x 2.tar.zip",
        /// never "x.tar.zip 2".
        @Test func uniqueKeepsTheExtensionLast() throws {
            let dir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("CompressDestinationTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }

            try Data().write(to: dir.appendingPathComponent("notes.tar.zip"))
            #expect(CompressDestination.unique(named: "notes.tar.zip", in: dir)
                .lastPathComponent == "notes.tar 2.zip")
        }
    }
}
