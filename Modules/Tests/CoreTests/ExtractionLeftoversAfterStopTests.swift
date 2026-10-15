//
//  ExtractionLeftoversAfterStopTests.swift
//  Modules
//
//  A work folder is noted while an extraction writes into it. Should the app
//  stop before the run ends, the next start finds the note and removes what
//  was left — only that, and only while it still is an unfinished work folder.
//

import Foundation
import Testing
@testable import Core

extension AllCoreTests {
    @MainActor struct ExtractionLeftoversAfterStopTests {

        private func makeFolder() throws -> URL {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("LeftoversAfterStopTests_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        /// A work folder as a run leaves it when the app stops: named and dated
        /// as one, with half an archive in it.
        private func leftover(in dir: URL, named name: String = "trip.macpack", busy: Bool = true) throws -> URL {
            let folder = dir.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("half".utf8).write(to: folder.appendingPathComponent("a.txt"))
            if busy {
                var url = folder
                var values = URLResourceValues()
                values.creationDate = ExtractionStaging.busyDate
                try url.setResourceValues(values)
            }
            return folder
        }

        /// A start that is not this one: the app as it ran before.
        private let earlierStart = "an earlier start"

        /// What this start of the app is writing is its own, never a leftover.
        @Test func aRunOfThisStartIsLeftAlone() throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            let store = isolatedDefaults()
            let folder = try leftover(in: dir)
            ExtractionStaging.note(folder, in: store)

            ExtractionStaging.removeLeftovers(in: store)

            #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("a.txt").path))
            #expect(noted(store)[folder.path] != nil)
        }

        private func noted(_ store: UserDefaults) -> [String: Any] {
            store.dictionary(forKey: ExtractionStaging.ledgerKey) ?? [:]
        }

        @Test func whatAStoppedRunLeftIsRemoved() throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            let store = isolatedDefaults()
            let folder = try leftover(in: dir)
            try Data("mine".utf8).write(to: dir.appendingPathComponent("mine.txt"))
            ExtractionStaging.note(folder, in: store, by: earlierStart)

            ExtractionStaging.removeLeftovers(in: store)

            #expect(!FileManager.default.fileExists(atPath: folder.path))
            #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("mine.txt").path))
            #expect(noted(store).isEmpty)
        }

        /// No longer marked unfinished, or no longer a work folder by its
        /// name: not ours to remove. The note goes all the same.
        @Test(arguments: [("trip.macpack", false), ("trip", true)])
        func whatIsNoLongerAWorkFolderStays(name: String, busy: Bool) throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            let store = isolatedDefaults()
            let folder = try leftover(in: dir, named: name, busy: busy)
            ExtractionStaging.note(folder, in: store, by: earlierStart)

            ExtractionStaging.removeLeftovers(in: store)

            #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("a.txt").path))
            #expect(noted(store).isEmpty)
        }

        @Test func aNoteWhoseFolderIsGoneIsDropped() throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            let store = isolatedDefaults()
            let folder = try leftover(in: dir)
            ExtractionStaging.note(folder, in: store, by: earlierStart)
            try FileManager.default.removeItem(at: folder)

            ExtractionStaging.removeLeftovers(in: store)
            #expect(noted(store).isEmpty)
        }

        /// A run that ends — whichever way — takes its note away: there is
        /// nothing for the next start to do.
        @Test(arguments: [true, false])
        func aRunThatEndsLeavesNoNote(commits: Bool) throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            let staging = try ExtractionStaging(in: dir, named: "trip")
            let key = staging.workFolder.path
            #expect(noted(.standard)[key] != nil)

            if commits {
                try staging.commit()
            } else {
                staging.discard()
            }
            #expect(noted(.standard)[key] == nil)
        }
    }
}
