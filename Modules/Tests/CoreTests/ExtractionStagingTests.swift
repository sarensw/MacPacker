//
//  ExtractionStagingTests.swift
//  Modules
//
//  `ExtractionStaging` by itself: the work folder an extraction writes into,
//  and how its content gets into the destination — or does not. No archive is
//  needed for any of it; the tests put into the work folder what an engine
//  would have. And `ExtractionFinderProgress`, which shows the run on that
//  folder in Finder.
//
//  What a commit does to items that are already in the destination is what the
//  engines did when they wrote into it directly (measured on both before this
//  type existed): a folder is extracted into, a file is replaced, a link stands
//  for what it points to, and what cannot be done fails. The difference is
//  *when* it fails — before anything has moved.
//

import Foundation
import Testing
@testable import Core

extension AllCoreTests {
    struct ExtractionStagingTests {

        private let fm = FileManager.default

        private func makeFolder() throws -> URL {
            let url = fm.temporaryDirectory
                .appendingPathComponent("ExtractionStagingTests_\(UUID().uuidString)")
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        /// Removes a test's folder, read-only items in it included.
        private func remove(_ folder: URL) {
            for path in (try? fm.subpathsOfDirectory(atPath: folder.path)) ?? [] {
                try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.appendingPathComponent(path).path)
            }
            try? fm.removeItem(at: folder)
        }

        private func write(_ text: String, to url: URL) throws {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }

        private func text(_ url: URL) throws -> String {
            String(decoding: try Data(contentsOf: url), as: UTF8.self)
        }

        /// Everything below `folder`, hidden items included, as sorted relative
        /// paths — folders with a trailing `/`, links with a trailing `@`.
        private func everything(in folder: URL) throws -> [String] {
            try fm.subpathsOfDirectory(atPath: folder.path).map { path in
                let type = try fm.attributesOfItem(atPath: folder.appendingPathComponent(path).path)[.type] as? FileAttributeType
                switch type {
                case .typeDirectory: return path + "/"
                case .typeSymbolicLink: return path + "@"
                default: return path
                }
            }.sorted()
        }

        private func creationDate(_ url: URL) throws -> Date? {
            try fm.attributesOfItem(atPath: url.path)[.creationDate] as? Date
        }

        private func mode(_ url: URL) throws -> Int {
            (try fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? -1
        }

        // MARK: - The work folder

        /// The item Finder shows while the run lasts: the archive's name, with
        /// the extension the app declares as its extraction package.
        @Test func theWorkFolderCarriesTheArchivesName() throws {
            let dest = try makeFolder()
            defer { remove(dest) }

            let staging = try ExtractionStaging(in: dest, named: "trip")

            #expect(staging.workFolder.deletingLastPathComponent().path == dest.path)
            #expect(staging.workFolder.lastPathComponent == "trip.macpack")
            #expect(try everything(in: dest) == ["trip.macpack/"])
        }

        /// Finder dims an item with this creation date and will not open it:
        /// its own mark for what it is still copying. The work folder is that
        /// for as long as it exists.
        @Test func theWorkFolderIsMarkedUnfinished() throws {
            let dest = try makeFolder()
            defer { remove(dest) }

            let staging = try ExtractionStaging(in: dest, named: "trip")

            #expect(try creationDate(staging.workFolder) == ExtractionStaging.busyDate)
            // 24 January 1984, 08:00 UTC
            #expect(ExtractionStaging.busyDate == ISO8601DateFormatter().date(from: "1984-01-24T08:00:00Z"))
        }

        /// A second run of the same archive into the same folder — or one after
        /// a crash left its work folder there — writes into a folder of its
        /// own, never into the one that is there.
        @Test func aWorkFolderWhoseNameIsTakenGetsANumber() throws {
            let dest = try makeFolder()
            defer { remove(dest) }

            let first = try ExtractionStaging(in: dest, named: "trip")
            try write("first", to: first.workFolder.appendingPathComponent("a.txt"))
            let second = try ExtractionStaging(in: dest, named: "trip")
            let third = try ExtractionStaging(in: dest, named: "trip")

            #expect(second.workFolder.lastPathComponent == "trip (2).macpack")
            #expect(third.workFolder.lastPathComponent == "trip (3).macpack")
            second.discard()
            third.discard()
            #expect(try everything(in: dest) == ["trip.macpack/", "trip.macpack/a.txt"])
        }

        /// An archive's name may be as long as a file name can be; with the
        /// extension on top it would be longer than one may be.
        @Test func aNameTooLongForAFileNameIsShortened() throws {
            let dest = try makeFolder()
            defer { remove(dest) }
            // 255 UTF-16 units once decomposed, which is how file urls carry it
            // — as long as a name may be, before anything is added to it
            let long = String(repeating: "é", count: 127) + "x"

            let staging = try ExtractionStaging(in: dest, named: long)

            let name = staging.workFolder.lastPathComponent
            #expect(fm.fileExists(atPath: staging.workFolder.path))
            #expect(name.decomposedStringWithCanonicalMapping.utf16.count <= 255)
            #expect(name.hasSuffix(".macpack"))
            #expect(name.hasPrefix("ééé"))
        }

        @Test func discardingLeavesTheDestinationAsItWas() throws {
            let dest = try makeFolder()
            defer { remove(dest) }
            try write("mine", to: dest.appendingPathComponent("mine.txt"))

            let staging = try ExtractionStaging(in: dest, named: "trip")
            try write("a", to: staging.workFolder.appendingPathComponent("a.txt"))
            try write("b", to: staging.workFolder.appending(path: "photos/b.jpg"))
            staging.discard()

            #expect(try everything(in: dest) == ["mine.txt"])
        }

        /// The XAD engine gives folders the permissions the archive holds, and
        /// a folder that may not be written does not let go of its content.
        @Test func discardingRemovesFoldersThatMayNotBeWritten() throws {
            let dest = try makeFolder()
            defer { remove(dest) }

            let staging = try ExtractionStaging(in: dest, named: "trip")
            let locked = staging.workFolder.appending(path: "photos/locked")
            try write("a", to: locked.appendingPathComponent("a.jpg"))
            try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
            staging.discard()

            #expect(try everything(in: dest) == [])
        }

        /// The engines create a destination that is not there yet; so does the
        /// work folder — and then a discarded run takes it along again.
        @Test func aMissingDestinationComesAndGoesWithTheWorkFolder() throws {
            let dir = try makeFolder()
            defer { remove(dir) }
            let dest = dir.appendingPathComponent("not there yet")

            let discarded = try ExtractionStaging(in: dest, named: "trip")
            try write("a", to: discarded.workFolder.appendingPathComponent("a.txt"))
            discarded.discard()
            #expect(!fm.fileExists(atPath: dest.path))

            let committed = try ExtractionStaging(in: dest, named: "trip")
            try write("a", to: committed.workFolder.appendingPathComponent("a.txt"))
            try committed.commit()
            #expect(try everything(in: dest) == ["a.txt"])
        }

        /// A destination that cannot be written says so in its own name, not
        /// in the work folder's.
        @Test func aDestinationThatCannotBeWrittenIsNamedInTheError() throws {
            let dest = try makeFolder()
            defer { remove(dest) }
            try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dest.path)

            do {
                _ = try ExtractionStaging(in: dest, named: "trip")
                Issue.record("a work folder was created in a folder that cannot be written")
            } catch {
                #expect(error.localizedDescription.contains(dest.lastPathComponent))
                #expect(!error.localizedDescription.contains(ExtractionStaging.workFolderExtension))
            }
        }

        // MARK: - Committing

        @Test func committingPutsTheItemsIntoTheDestination() throws {
            let dest = try makeFolder()
            defer { remove(dest) }
            try write("mine", to: dest.appendingPathComponent("mine.txt"))

            let staging = try ExtractionStaging(in: dest, named: "trip")
            try write("a", to: staging.workFolder.appendingPathComponent("a.txt"))
            try write("b", to: staging.workFolder.appending(path: "photos/sub/b.jpg"))
            try staging.commit()

            #expect(try everything(in: dest) == ["a.txt", "mine.txt", "photos/", "photos/sub/", "photos/sub/b.jpg"])
        }

        @Test func committingAsAContainerMakesTheWorkFolderThatContainer() throws {
            let dest = try makeFolder()
            defer { remove(dest) }

            let staging = try ExtractionStaging(in: dest, named: "trip")
            try write("a", to: staging.workFolder.appendingPathComponent("a.txt"))
            try write("b", to: staging.workFolder.appending(path: "photos/b.jpg"))
            let begun = Date()
            try staging.commit(as: dest.appendingPathComponent("trip"))

            #expect(try everything(in: dest) == ["trip/", "trip/a.txt", "trip/photos/", "trip/photos/b.jpg"])
            // The result is finished, and must not go on looking otherwise: it
            // is the work folder under another name, and would keep its mark.
            let created = try #require(try creationDate(dest.appendingPathComponent("trip")))
            #expect(created != ExtractionStaging.busyDate)
            #expect(abs(created.timeIntervalSince(begun)) < 60)
        }

        @Test func committingMergesIntoFoldersAndReplacesFiles() throws {
            let dest = try makeFolder()
            defer { remove(dest) }
            try write("old", to: dest.appending(path: "photos/a.jpg"))
            try write("mine", to: dest.appending(path: "photos/sub/mine.txt"))

            let staging = try ExtractionStaging(in: dest, named: "trip")
            try write("new", to: staging.workFolder.appending(path: "photos/a.jpg"))
            try write("b", to: staging.workFolder.appending(path: "photos/sub/b.jpg"))
            try write("c", to: staging.workFolder.appending(path: "photos/new/c.jpg"))
            try staging.commit()

            #expect(try everything(in: dest) == [
                "photos/", "photos/a.jpg",
                "photos/new/", "photos/new/c.jpg",
                "photos/sub/", "photos/sub/b.jpg", "photos/sub/mine.txt",
            ])
            #expect(try text(dest.appending(path: "photos/a.jpg")) == "new")
            #expect(try text(dest.appending(path: "photos/sub/mine.txt")) == "mine")
        }

        /// A link in the destination stands for what it points to, as it did
        /// when the engines wrote into the destination themselves: a link to a
        /// folder is extracted into, a link to a file has that file replaced.
        @Test func committingGoesThroughLinks() throws {
            let dir = try makeFolder()
            defer { remove(dir) }
            let dest = dir.appendingPathComponent("out")
            let elsewhere = dir.appendingPathComponent("elsewhere")
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            try write("old", to: elsewhere.appendingPathComponent("notes.txt"))
            try fm.createSymbolicLink(at: dest.appendingPathComponent("photos"), withDestinationURL: elsewhere)
            try fm.createSymbolicLink(at: dest.appendingPathComponent("notes.txt"), withDestinationURL: elsewhere.appendingPathComponent("notes.txt"))

            let staging = try ExtractionStaging(in: dest, named: "trip")
            try write("a", to: staging.workFolder.appending(path: "photos/a.jpg"))
            try write("new", to: staging.workFolder.appendingPathComponent("notes.txt"))
            try staging.commit()

            #expect(try everything(in: dest) == ["notes.txt@", "photos@"])
            #expect(try everything(in: elsewhere) == ["a.jpg", "notes.txt"])
            #expect(try text(elsewhere.appendingPathComponent("notes.txt")) == "new")
        }

        /// A folder's own dates and permissions come from the archive, set by
        /// the engine when it is done with the folder. Moving it must not cost
        /// them — and moving a folder that may not be written to another parent
        /// is something the system refuses outright.
        @Test func anExtractedFolderKeepsItsDateAndPermissions() throws {
            let dest = try makeFolder()
            defer { remove(dest) }
            let then = Date(timeIntervalSince1970: 1_000_000_000)

            let staging = try ExtractionStaging(in: dest, named: "trip")
            let locked = staging.workFolder.appendingPathComponent("locked")
            try write("a", to: locked.appendingPathComponent("a.jpg"))
            try fm.setAttributes([.posixPermissions: 0o555, .modificationDate: then], ofItemAtPath: locked.path)
            try staging.commit()

            #expect(try everything(in: dest) == ["locked/", "locked/a.jpg"])
            let moved = try fm.attributesOfItem(atPath: dest.appendingPathComponent("locked").path)
            #expect((moved[.posixPermissions] as? NSNumber)?.intValue == 0o555)
            #expect(moved[.modificationDate] as? Date == then)
        }

        /// The same folder, but one of its name is already there: it is merged
        /// away rather than moved, and has to let go of its content first.
        @Test func anExtractedFolderThatMayNotBeWrittenStillMerges() throws {
            let dest = try makeFolder()
            defer { remove(dest) }
            try write("mine", to: dest.appending(path: "photos/mine.txt"))

            let staging = try ExtractionStaging(in: dest, named: "trip")
            let locked = staging.workFolder.appendingPathComponent("photos")
            try write("a", to: locked.appendingPathComponent("a.jpg"))
            try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
            try staging.commit()

            #expect(try everything(in: dest) == ["photos/", "photos/a.jpg", "photos/mine.txt"])
            // the folder that was there keeps what it had
            #expect(try mode(dest.appendingPathComponent("photos")) == 0o755)
        }

        /// Where the new file cannot be renamed onto the old one — the old one
        /// sits behind a link, on another volume — it is copied beside it and
        /// swapped in. The old file must outlive a copy that fails: the run is
        /// discarded then, and with the old file removed first both would be
        /// gone.
        @Test func aReplacementByCopyKeepsTheOldFileUntilTheNewOneIsWhole() throws {
            let dir = try makeFolder()
            defer { remove(dir) }
            let old = dir.appendingPathComponent("photo.jpg")
            let new = dir.appending(path: "work/photo.jpg")
            try write("old", to: old)
            try write("new", to: new)

            try ExtractionStaging.replace(old, withCopyOf: new)
            #expect(try text(old) == "new")
            // nothing left beside it, and no second copy in the work folder
            #expect(try everything(in: dir) == ["photo.jpg", "work/"])

            // a copy that cannot be made
            try write("old", to: old)
            #expect(throws: (any Error).self) {
                try ExtractionStaging.replace(old, withCopyOf: dir.appending(path: "work/not-there.jpg"))
            }
            #expect(try text(old) == "old")
            #expect(try everything(in: dir) == ["photo.jpg", "work/"])
        }

        // MARK: - What cannot be committed

        enum Clash: CaseIterable {
            case fileWhereAFolderGoes, folderWhereAFileGoes, brokenLink, fileThatCannotBeWritten, folderThatCannotBeWritten
        }

        /// The engines failed on each of these as well, part-way through.
        /// A commit finds them before anything has moved: `a.txt`, first in
        /// line and free to go, is not in the destination either.
        @Test(arguments: Clash.allCases)
        func aClashStopsTheCommitBeforeAnythingMoves(clash: Clash) throws {
            let dest = try makeFolder()
            defer { remove(dest) }
            let staging = try ExtractionStaging(in: dest, named: "trip")
            try write("a", to: staging.workFolder.appendingPathComponent("a.txt"))

            switch clash {
            case .fileWhereAFolderGoes:
                try write("mine", to: dest.appendingPathComponent("photos"))
                try write("b", to: staging.workFolder.appending(path: "photos/b.jpg"))
            case .folderWhereAFileGoes:
                try write("mine", to: dest.appending(path: "photos/b.jpg/mine.txt"))
                try write("b", to: staging.workFolder.appending(path: "photos/b.jpg"))
            case .brokenLink:
                try fm.createSymbolicLink(atPath: dest.appendingPathComponent("photos").path, withDestinationPath: "/nowhere/at/all")
                try write("b", to: staging.workFolder.appending(path: "photos/b.jpg"))
            case .fileThatCannotBeWritten:
                try write("mine", to: dest.appending(path: "photos/b.jpg"))
                try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: dest.appending(path: "photos/b.jpg").path)
                try write("b", to: staging.workFolder.appending(path: "photos/b.jpg"))
            case .folderThatCannotBeWritten:
                try write("mine", to: dest.appending(path: "photos/mine.txt"))
                try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dest.appendingPathComponent("photos").path)
                try write("b", to: staging.workFolder.appending(path: "photos/b.jpg"))
            }
            let before = try everything(in: dest).filter { !$0.hasPrefix(staging.workFolder.lastPathComponent) }

            #expect(throws: ArchiveError.self) { try staging.commit() }
            staging.discard()

            #expect(try everything(in: dest) == before)
            #expect(!fm.fileExists(atPath: dest.appendingPathComponent("a.txt").path))
        }

        // MARK: - The run, shown in Finder

        /// Finder draws what is published here; whether it does is Finder's
        /// business. What the app owes it is a figure that follows the engine,
        /// and an indicator that comes down — once — before the folder moves.
        @Test func theIndicatorFollowsTheEngineAndComesDown() throws {
            let dest = try makeFolder()
            defer { remove(dest) }
            let staging = try ExtractionStaging(in: dest, named: "trip")

            let inFinder = ExtractionFinderProgress(on: staging.workFolder, totalBytes: nil)
            #expect(inFinder.isPublished)
            // no total from the listing, none from the engine yet
            #expect(inFinder.fractionCompleted == nil)

            inFinder.report(completed: 250, total: 1000)
            #expect(inFinder.fractionCompleted == 0.25)

            inFinder.end()
            #expect(!inFinder.isPublished)
            inFinder.end()
            #expect(!inFinder.isPublished)
            staging.discard()
        }

        @Test func theIndicatorStartsFromTheListedSize() throws {
            let dest = try makeFolder()
            defer { remove(dest) }
            let staging = try ExtractionStaging(in: dest, named: "trip")

            let inFinder = ExtractionFinderProgress(on: staging.workFolder, totalBytes: 4000)
            #expect(inFinder.fractionCompleted == 0)
            // an engine that counts past its own total does not overshoot
            inFinder.report(completed: 5000, total: 4000)
            #expect(inFinder.fractionCompleted == 1)

            inFinder.end()
            staging.discard()
        }
    }
}
