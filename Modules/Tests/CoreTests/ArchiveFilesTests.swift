//
//  ArchiveFilesTests.swift
//  Modules
//
//  "Move archive to Trash after extraction" moves the archive's files: its own
//  file, or every volume of a split one — and nothing else from its folder,
//  however close its name.
//

import Foundation
import Testing
@testable import Core

extension AllCoreTests {
    @MainActor struct ArchiveFilesTests {

        private let folder = URL(fileURLWithPath: "/tmp/archives", isDirectory: true)

        private func files(of name: String, among names: [String]) -> [String] {
            let siblings = names.map { folder.appendingPathComponent($0) }
            return ArchiveFiles.files(
                of: folder.appendingPathComponent(name),
                among: siblings,
                splits: ArchiveTypeCatalog().allSplits()
            ).map(\.lastPathComponent)
        }

        @Test func aPlainArchiveIsItsOwnFile() {
            #expect(files(of: "trip.zip", among: ["trip.zip", "other.zip", "trip.txt"]) == ["trip.zip"])
        }

        /// The loader opens a spanned set at its first volume; the bare `.zip`
        /// is its last.
        @Test func aSpannedZipIsEveryVolumeAndItsBareZip() {
            let names = ["trip.z01", "trip.z02", "trip.zip", "other.z01", "other.zip", "trip.txt"]
            #expect(files(of: "trip.z01", among: names) == ["trip.z01", "trip.z02", "trip.zip"])
        }

        /// `trip.zip.001` and its volumes are one archive; `trip.zip` beside
        /// them is another.
        @Test(arguments: ["zip", "7z"])
        func aNumberedSetLeavesTheArchiveOfTheSameName(format: String) {
            let names = ["trip.\(format)", "trip.\(format).001", "trip.\(format).002", "trip.\(format).003", "other.\(format).001"]
            #expect(files(of: "trip.\(format).001", among: names)
                    == ["trip.\(format).001", "trip.\(format).002", "trip.\(format).003"])
            #expect(files(of: "trip.\(format)", among: names) == ["trip.\(format)"])
        }

        @Test func rarVolumesGoTogether() {
            let parts = ["trip.part1.rar", "trip.part2.rar", "trip.part10.rar", "other.part1.rar", "trip.rar"]
            #expect(files(of: "trip.part1.rar", among: parts) == ["trip.part1.rar", "trip.part10.rar", "trip.part2.rar"])

            let older = ["trip.rar", "trip.r00", "trip.r01", "triple.r00", "trip.zip"]
            #expect(files(of: "trip.rar", among: older) == ["trip.rar", "trip.r00", "trip.r01"])
        }

        @Test func namesMatchWhateverTheirCase() {
            #expect(files(of: "Trip.z01", among: ["Trip.z01", "TRIP.Z02", "trip.zip"]) == ["Trip.z01", "TRIP.Z02", "trip.zip"])
        }

        // MARK: - From an opened archive

        private func makeFolder() throws -> URL {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("ArchiveFilesTests_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        /// Zips `content` as `trip.zip` in `dir` with the system `zip`;
        /// `split` splits it into volumes of that size.
        private func makeZip(in dir: URL, content: Data, split: String? = nil) throws {
            try content.write(to: dir.appendingPathComponent("data.bin"))
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            p.arguments = (split.map { ["-s", $0] } ?? []) + ["-0", "trip.zip", "data.bin"]
            p.currentDirectoryURL = dir
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run()
            p.waitUntilExit()
            #expect(p.terminationStatus == 0)
            try FileManager.default.removeItem(at: dir.appendingPathComponent("data.bin"))
        }

        private func opened(_ url: URL) async throws -> ArchiveState {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            // a split archive's other volumes are read only once access to
            // their folder is granted, which the app asks the user for
            state.folderAccessProvider = { _ in true }
            state.open(url: url)
            try await state.openTask?.value
            return state
        }

        @Test func anOpenedArchiveKnowsItsFiles() async throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            try makeZip(in: dir, content: Data("hello".utf8))
            FileManager.default.createFile(atPath: dir.appendingPathComponent("trip.zip.001").path, contents: Data())

            let state = try await opened(dir.appendingPathComponent("trip.zip"))
            #expect(state.filesOnDisk().map(\.lastPathComponent) == ["trip.zip"])
        }

        /// Opened at its last volume, a spanned zip is read from its first — and
        /// all of its volumes are its files.
        @Test func aSpannedZipOpenedAtItsLastVolumeKnowsEveryVolume() async throws {
            let dir = try makeFolder()
            defer { try? FileManager.default.removeItem(at: dir) }
            var noise = SystemRandomNumberGenerator()
            try makeZip(in: dir, content: Data((0..<200_000).map { _ in UInt8.random(in: 0...255, using: &noise) }), split: "64k")
            #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("trip.z01").path))

            let state = try await opened(dir.appendingPathComponent("trip.zip"))
            #expect(state.filesOnDisk().map(\.lastPathComponent) == ["trip.z01", "trip.z02", "trip.z03", "trip.zip"])
        }

        /// Its folder unreadable, a split archive's other volumes cannot be
        /// found: then none of its files is named, not just the one opened.
        @Test func anArchiveWhoseFolderCannotBeReadHasNoFiles() async throws {
            let dir = try makeFolder()
            defer {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
                try? FileManager.default.removeItem(at: dir)
            }
            try makeZip(in: dir, content: Data("hello".utf8))
            let state = try await opened(dir.appendingPathComponent("trip.zip"))
            // write and enter, but not list
            try FileManager.default.setAttributes([.posixPermissions: 0o300], ofItemAtPath: dir.path)

            #expect(state.filesOnDisk().isEmpty)
        }

        @Test func aNeverSavedArchiveHasNoFiles() {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            #expect(state.filesOnDisk().isEmpty)
        }
    }
}
