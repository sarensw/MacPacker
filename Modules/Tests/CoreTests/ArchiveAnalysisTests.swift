//
//  ArchiveAnalysisTests.swift
//  Modules
//
//  Created by Claude on 16.11.26.
//

import Testing
import Foundation
@testable import Core
import tb

/// What a user can send about an archive they cannot share: the analysis from
/// Settings, and the logs of opening it (#413).
extension AllCoreTests {

    @MainActor struct ArchiveAnalysisTests {

        private func fixture(_ path: String) -> URL {
            let parts = path.split(separator: "/", maxSplits: 1)
            return Bundle.module.url(forResource: String(parts[0]), withExtension: nil)!
                .appendingPathComponent(String(parts[1]))
        }

        /// As the app has it: engines picked automatically, for every format.
        private func analyzer() -> ArchiveAnalyzer {
            let catalog = ArchiveTypeCatalog()
            let store = ArchiveEngineConfigStore(catalog: catalog, defaults: isolatedDefaults())
            return ArchiveAnalyzer(catalog: catalog, engineSelector: ArchiveEngineSelector(catalog: catalog, configStore: store))
        }

        @Test func aZipIsDescribedByItsFileDetectionAnd7Zip() async throws {
            let analysis = await analyzer().report(for: fixture("defaultArchives/defaultArchive.zip"))

            let file = try #require(analysis.section("File"))
            #expect(file.value("Name") == "defaultArchive.zip")
            #expect(file.value("Extension") == "zip")
            #expect(file.value("Size")?.hasPrefix("53261 bytes") == true)

            let detection = try #require(analysis.section("Detection"))
            // zipx shares zip's signature; detection goes by the first
            #expect(detection.value("By content") == "zip at 0; zipx at 0")
            #expect(detection.value("First 8 bytes") == nil)
            #expect(detection.value("Opens as") == "zip (from fileExtension)")
            #expect(detection.value("Selected") == "7zip")

            let sevenZip = try #require(analysis.section("7-Zip"))
            #expect(sevenZip.value("Opened as") == "zip")
            #expect(sevenZip.value("Files") == "3")
            #expect(sevenZip.value("Folders") == "1")
            #expect(sevenZip.value("Size")?.hasPrefix("52784 bytes") == true)
            #expect(analysis.section("7-Zip archive properties")?.value("Physical size") == "53261")
        }

        /// Each engine the catalog has for the format lists it the way opening
        /// it would, so a report shows which of them can.
        @Test func everyEngineForTheFormatListsIt() async {
            let analysis = await analyzer().report(for: fixture("defaultArchives/defaultArchive.zip"))

            #expect(analysis.section("Engine: 7-Zip")?.value("Entries") == "4")
            #expect(analysis.section("Engine: XAD (The Unarchiver)")?.value("Entries") == "4")
        }

        /// The report names the archive and none of the files in it, so it can
        /// be sent as it is.
        @Test func theFilesInTheArchiveAreNotNamed() async {
            let text = await analyzer().report(for: fixture("defaultArchives/defaultArchive.zip")).text

            #expect(text.contains("defaultArchive.zip"))
            for name in ["hello world", "README", "NestedArchive", "folder/"] {
                #expect(!text.contains(name), "\(name) is in the report")
            }
        }

        /// Nor the user's own folders: only which of the usual places it is in.
        @Test(arguments: [
            ("Documents/Clients/Acme/x.zip", "~/Documents/…"),
            ("Downloads/x.zip", "~/Downloads"),
            ("x.zip", "~"),
            ("Library/Mobile Documents/com~apple~CloudDocs/Taxes/x.zip", "iCloud Drive"),
            ("Library/CloudStorage/Dropbox/Private/x.zip", "~/Library/CloudStorage/Dropbox"),
        ])
        func theLocationLeavesOutTheUsersFolderNames(path: String, shown: String) {
            let home = String(cString: getpwuid(getuid()).pointee.pw_dir)

            #expect(ArchiveAnalyzer.location(of: URL(fileURLWithPath: "\(home)/\(path)")) == shown)
        }

        /// A comment is the user's own words: only its length is shown.
        @Test func theArchiveCommentIsShownByItsLengthOnly() async {
            let analysis = await analyzer().report(for: fixture("zip/split_zipjs64comment.zip"))

            #expect(analysis.section("7-Zip archive properties")?.value("Comment")?.hasSuffix(" characters>") == true)
            #expect(!analysis.text.contains("A zip comment"))
        }

        @Test func aFileOnAnotherVolumeIsNotNamedEither() {
            #expect(ArchiveAnalyzer.location(of: URL(fileURLWithPath: "/Volumes/Gustavo's Disk/x.zip")) == "/Volumes/…")
        }

        /// A signature is looked for where the format has it, not only at the
        /// start. And an archive's raw bytes stay out: a tar starts with the
        /// name of its first entry.
        @Test(arguments: [
            ("defaultArchives/defaultArchive.tar", "tar at 257"),
            ("defaultArchives/defaultArchive.iso", "iso at 32769, 34817, 36865"),
            ("defaultArchives/defaultArchive.dmg", "dmg at end − 512"),
            ("defaultArchives/defaultArchive.vdi", "vdi at 64"),
        ])
        func signaturesAreFoundWhereTheFormatHasThem(path: String, signature: String) async {
            let analysis = await analyzer().report(for: fixture(path))

            #expect(analysis.section("Detection")?.value("By content") == signature)
            #expect(analysis.section("Detection")?.value("First 8 bytes") == nil)
            #expect(!analysis.text.contains("66 6F 6C 64 65 72"), "a name in hex: folder")
        }

        /// What made 7-Zip stop reading a damaged archive.
        @Test func aDamagedArchiveShowsWhat7ZipFound() async {
            let analysis = await analyzer().report(for: fixture("damaged/truncated.zip"))

            #expect(analysis.section("7-Zip archive properties")?.value("Error flags")?.contains("unexpectedEnd") == true)
        }

        /// Every archive property 7-Zip reports for the default archives has a
        /// name and a value: a "Property 49" row tells nobody anything.
        @Test func everyArchivePropertyOfTheDefaultArchivesIsNamed() async throws {
            let folder = try #require(Bundle.module.url(forResource: "defaultArchives", withExtension: nil))
            let analyzer = analyzer()
            for url in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                let rows = await analyzer.report(for: url).section("7-Zip archive properties")?.rows ?? []
                for row in rows {
                    #expect(!row.label.contains("Property "), "\(url.lastPathComponent): \(row.label)")
                    #expect(!row.value.isEmpty, "\(url.lastPathComponent): \(row.label)")
                }
            }
        }

        /// An archive whose names need a password says so, and the analysis
        /// goes on to the end without anyone being asked for one.
        @Test func encryptedNamesAreReportedWithoutAPassword() async {
            let analysis = await analyzer().report(for: fixture("password/7z_encrypted_header.7z"))

            #expect(analysis.section("7-Zip")?.value("Opened")?.contains("a password is needed") == true)
            #expect(analysis.sections.last?.title.hasPrefix("Engine:") == true)
        }

        /// A file MacPacker does not read is still described, up to detection.
        @Test func aFileThatIsNoArchiveIsStillDescribed() async {
            let analysis = await analyzer().report(for: fixture("defaultArchiveContent/hello world.txt"))

            #expect(analysis.section("File")?.value("Size")?.hasPrefix("13 bytes") == true)
            #expect(analysis.section("Detection")?.value("Opens as") == "not an archive MacPacker reads")
            #expect(analysis.section("Detection")?.value("By content") == "none")
            // all a file nothing knows can be told by: "Hello Wo"
            #expect(analysis.section("Detection")?.value("First 8 bytes") == "48 65 6C 6C 6F 20 57 6F")
            #expect(!analysis.sections.contains { $0.title.hasPrefix("Engine:") })
        }

        /// Each step is announced before it runs: a report taken while one
        /// hangs says which.
        @Test func everyStepIsAnnouncedBeforeItRuns() async {
            var events: [String] = []
            for await progress in analyzer().analyze(fixture("defaultArchives/defaultArchive.zip")) {
                switch progress {
                case .step(let title): events.append("step \(title)")
                case .section(let section): events.append("section \(section.title)")
                }
            }

            let steps = events.indices.filter { events[$0].hasPrefix("step ") }
            #expect(steps.count >= 6)
            for index in steps {
                #expect(events[index + 1] == "section " + events[index].dropFirst("step ".count))
            }
        }

        @Test func aReportTakenWhileAStepRunsNamesIt() {
            var analysis = ArchiveAnalysis()
            analysis.apply(.section(.init(title: "File", rows: [.init(label: "Name", value: "x.zip")])))
            analysis.apply(.step("7-Zip"))

            #expect(analysis.text.hasSuffix("Still running: 7-Zip\n"))
        }
    }

    /// The logs a user exports from Settings say how far an open got (#413).
    @MainActor struct OpenLogTests {

        @Test func theStepsOfAnOpenAreInTheExportedLogsInOrder() async throws {
            let since = Date()
            let url = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
                .appendingPathComponent("defaultArchive.zip")
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.open(url: url)
            try await state.openTask?.value

            let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).ndjson")
            defer { try? FileManager.default.removeItem(at: file) }
            try tb.exportRecentLogs(since: since, to: file)
            let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
                .filter { $0.contains("defaultArchive.zip") }

            // each after the one before: the export can begin a little before
            // `since`, with what an earlier test logged
            var position = lines.startIndex
            for step in ["Opening archive", "Archive type detected", "Engine selected", "7-Zip opening",
                         "7-Zip opened", "Entries listed", "Archive ready to display"] {
                guard let found = lines[position...].firstIndex(where: { $0.contains("\"\(step) ⟦tb1⟧") }) else {
                    Issue.record("\(step) is not logged after the step before it")
                    return
                }
                position = found
            }
        }
    }
}
