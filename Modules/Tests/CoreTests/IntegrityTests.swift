//
//  IntegrityTests.swift
//  Modules
//
//  Testing an archive (#232): every entry has to decompress and match its
//  checksum, and nothing is written. A test that missed damage would be worse
//  than no test, so every way an archive can be damaged that the fixtures in
//  `damaged/` hold has to come out as damaged, naming what is — and every
//  archive that is whole has to come out as whole.
//

import Foundation
import Testing
import tb
@testable import Core

extension AllCoreTests {
    @MainActor struct IntegrityTests {

        /// `folder/name` in the test bundle.
        private func fixture(_ path: String) -> URL {
            let parts = path.split(separator: "/", maxSplits: 1)
            return Bundle.module.url(forResource: String(parts[0]), withExtension: nil)!
                .appendingPathComponent(String(parts[1]))
        }

        /// Tests `url` the way the File menu and Finder's "Test Archive" do, and
        /// hands back the job it ended in.
        private func test(
            _ url: URL,
            engines: any ArchiveEngineSelectorProtocol = ArchiveEngineSelector7zip(),
            password: String? = nil
        ) async throws -> ExtractionJob {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: engines)
            let center = ExtractionProgressCenter()
            state.progressCenter = center
            // Unsandboxed tests can already read the folder, so grant unconditionally.
            state.folderAccessProvider = { _ in true }
            state.passwordProvider = { _ in password }
            await state.test(url).value
            return try #require(center.jobs.first)
        }

        /// Every archive that is whole tests as whole, whatever its format. The
        /// compounds are tested as the compressed file around the tar.
        @Test(arguments: [
            "7z", "arj", "ar", "cab", "cpio", "lzh", "rar", "tar", "xar", "zip", "jar",
            "rpm", "exe", "dmg", "fat", "iso", "qcow2", "squashfs", "vdi", "vhd", "vhdx",
            "vmdk", "wim", "tar.bz2", "tar.gz", "tar.lzma", "tar.xz", "tar.Z", "tgz", "txz",
        ])
        func aWholeArchiveTestsWhole(ext: String) async throws {
            let job = try await test(fixture("defaultArchives/defaultArchive.\(ext)"))

            #expect(job.kind == .test)
            #expect(job.state == .done)
            #expect(job.testResult == ArchiveTestResult(damagedEntries: []))
        }

        /// A Nextcloud download warns of a headers error, and holds nothing that
        /// is wrong: 7-Zip tests it OK, and a warning is not damage.
        @Test func aWarningIsNotDamage() async throws {
            let job = try await test(fixture("zip/zipstreamer64.zip"))

            #expect(job.state == .done)
            #expect(job.testResult?.isIntact == true)
        }

        /// A file compressed with a method 7-Zip can't decode is neither whole
        /// nor damaged: the test says it can't be checked, and checks the file
        /// beside it as usual.
        @Test func aFileWithAnUnsupportedMethodCantBeChecked() async throws {
            let job = try await test(fixture("zip/unsupportedMethod.zip"))

            #expect(job.testResult == ArchiveTestResult(damagedEntries: [], uncheckedEntries: ["sound.wav"]))
            #expect(job.hasOutcomeToShow)
        }

        /// What is damaged is named, and only that: an archive with one damaged
        /// entry has others that are fine. An archive cut short says so itself,
        /// also where every entry that is left reads, and so does one whose own
        /// checksum no longer matches, of which 7-Zip only warns; each says
        /// which, so that the verdict can say why. In an encrypted archive, what
        /// fails after an entry decrypted and matched is damaged: the password
        /// was right, and asking again can't help.
        @Test(arguments: [
            ("damaged/crc.zip", ["folder/README.md"], nil),
            ("damaged/crc.7z", ["folder/NestedArchive.zip"], nil),
            ("damaged/crc.tar.gz", ["crc.tar"], nil),
            ("damaged/truncated.zip", ["folder/NestedArchive.zip"], .endsEarly),
            ("damaged/noCentralDirectory.zip", [], .endsEarly),
            ("damaged/crc.dmg", [], .checksum),
            ("damaged/tocChecksum.xar", [], .checksum),
            ("damaged/crcEncrypted.7z", ["folder/README.md", "hello world.txt"], nil),
        ] as [(String, [String], ArchiveDamage?)])
        func damageIsFoundAndNamed(arg: (String, [String], ArchiveDamage?)) async throws {
            let job = try await test(fixture(arg.0), password: "password")

            #expect(job.testResult == ArchiveTestResult(damagedEntries: arg.1, archiveDamage: arg.2))
            guard case .failed = job.state else {
                Issue.record("\(arg.0) ended \(job.state), not failed")
                return
            }
            #expect(job.hasOutcomeToShow)
        }

        /// Why an archive is damaged is in the logs a user exports from Settings
        /// to send us.
        @Test func whyAnArchiveIsDamagedIsInTheExportedLogs() async throws {
            let since = Date()
            _ = try await test(fixture("damaged/noCentralDirectory.zip"))

            let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).ndjson")
            defer { try? FileManager.default.removeItem(at: file) }
            try tb.exportRecentLogs(since: since, to: file)
            let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")

            #expect(lines.contains { $0.contains("noCentralDirectory.zip") && $0.contains("endsEarly") })
            #expect(lines.contains { $0.contains("noCentralDirectory.zip") && $0.contains("unexpectedEnd") })
        }

        /// A compound is tested as the compressed file it is, and nothing is
        /// decompressed to disk on the way: opening it would write the tar to a
        /// temp folder first.
        @Test func aCompoundIsTestedWithoutWritingTheTar() async throws {
            let temp = try #require(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
                .appendingPathComponent("ta", isDirectory: true)
            let before = (try? FileManager.default.contentsOfDirectory(atPath: temp.path)) ?? []

            let job = try await test(fixture("defaultArchives/defaultArchive.tar.gz"))

            #expect(job.state == .done)
            #expect(((try? FileManager.default.contentsOfDirectory(atPath: temp.path)) ?? []) == before)
        }

        /// Any part of a split set tests the whole set, through its first volume.
        @Test(arguments: ["zip/split_pk.zip", "zip/split_7zz.zip.003"])
        func anyPartOfASplitTestsTheWholeSet(part: String) async throws {
            let job = try await test(fixture(part))

            #expect(job.state == .done)
            #expect(job.testResult?.isIntact == true)
        }

        /// An encrypted archive is decrypted to be tested, with the password it
        /// is asked for; the name of an encrypted header too.
        @Test(arguments: ["password/zip_aes256.zip", "password/7z_aes256.7z", "password/7z_encrypted_header.7z"])
        func anEncryptedArchiveTestsWithItsPassword(path: String) async throws {
            let job = try await test(fixture(path), password: "password")

            #expect(job.state == .done)
            #expect(job.testResult?.isIntact == true)
        }

        /// A wrong password is asked again, not taken for damage: nothing has
        /// decrypted yet to prove it right, the folder stored before the files
        /// without encryption no more than anything else.
        @Test func aWrongPasswordIsAskedAgain() async throws {
            let result = try await Archive7ZipEngine().test(
                fixture("password/7z_aes256.7z"),
                passwordResolver: { $0.attempt == 1 ? "wrong" : "password" },
                onProgress: nil)

            #expect(result.isIntact)
        }

        /// Without the password there is nothing to decode, so there is no
        /// verdict either: a cancelled prompt is a cancelled test.
        @Test func aCancelledPasswordPromptCancelsTheTest() async throws {
            let job = try await test(fixture("password/7z_aes256.7z"), password: nil)

            #expect(job.state == .cancelled)
            #expect(job.testResult == nil)
            #expect(!job.hasOutcomeToShow)
        }

        /// The progress callback stops a test as it stops an extraction.
        @Test func aTestStopsWhenProgressSaysSo() async throws {
            await #expect(throws: CancellationError.self) {
                _ = try await Archive7ZipEngine().test(
                    fixture("defaultArchives/defaultArchive.zip"),
                    passwordResolver: { _ in nil },
                    onProgress: { _, _ in false })
            }
        }

        /// A format no engine can test says so about the format: which engine
        /// reads it is nothing a user picked or needs to know. Only XAD reads
        /// StuffIt, and the catalog declares `test` for 7-Zip alone.
        @Test func aFormatNoEngineCanTestSaysSo() async throws {
            let job = try await test(fixture("stuffit/testfile.stuffit7_dlx.macx1.sit"))

            #expect(job.state == .failed("Testing isn't supported for this format."))
            #expect(job.testResult == nil)
        }

        /// A test runs on the engine the catalog says can test the format,
        /// whichever engine was picked to open it: here XAD, which cannot test,
        /// nor read a split set.
        @Test(arguments: [
            ("damaged/crc.zip", ["folder/README.md"]),
            ("zip/split_pk.zip", []),
        ])
        func aTestRunsOnTheEngineThatCanTest(arg: (String, [String])) async throws {
            let catalog = ArchiveTypeCatalog()
            let store = ArchiveEngineConfigStore(catalog: catalog, defaults: isolatedDefaults())
            store.isAutomatic = false
            store.setSelectedEngine(.xad, for: "zip")

            let job = try await test(
                fixture(arg.0),
                engines: ArchiveEngineSelector(catalog: catalog, configStore: store))

            #expect(job.testResult == ArchiveTestResult(damagedEntries: arg.1))
        }

        /// The toolbar tests the archive the window opened, under that
        /// archive's name, also while the window shows a nested archive.
        @Test func theVerdictNamesTheArchiveTested() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let center = ExtractionProgressCenter()
            state.progressCenter = center
            state.open(url: fixture("defaultArchives/defaultArchive.zip"))
            try await state.openTask?.value
            let folder = try #require(state.root?.children?.compactMap { state.entries[$0] }.first { $0.type == .directory })
            try await state.openAsync(item: folder)
            try await state.openAsync(item: try #require(state.childItems?.first { $0.name == "NestedArchive.zip" }))
            #expect(state.name == "NestedArchive.zip")

            await state.test(try #require(state.url)).value

            #expect(center.jobs.first?.archiveName == "defaultArchive.zip")
        }
    }
}
