//
//  SaveOptionsStateTests.swift
//  Modules
//
//  The app's side of the save options: the model the save panel binds to —
//  what it offers, what it remembers, what it hands the writer — and the
//  save itself as the archive window runs it: leaving `.DS_Store` out, asking
//  for the password of an encrypted source, reopening a split archive.
//

import Testing
import Foundation
import Swift7zip
@testable import Core

/// Counts how often the password prompt came up. Suites here run serialized.
private final class Prompts: @unchecked Sendable {
    var count = 0
    var answers: [String?]
    init(_ answers: [String?]) { self.answers = answers }
    func next() -> String? {
        defer { count += 1 }
        return count < answers.count ? answers[count] : answers.last ?? nil
    }
}

/// Entry paths as stored, sidecars included, from a reader that folds nothing.
private func storedPaths(_ archive: URL) throws -> [String] {
    guard archive.pathExtension == "zip" else {
        return try SevenZipArchive(url: archive).entries.map(\.path)
    }
    return try systemZipEntries(archive)
}

extension AllCoreTests {

    // MARK: - The options model

    @MainActor struct ArchiveSaveOptionsTests {

        @Test func aFirstSaveStartsFromTheDefaults() {
            let options = ArchiveSaveOptions(defaults: isolatedDefaults())
            #expect(options.format == .zip)
            #expect(options.level == 5)
            #expect(options.method == nil && options.dictionarySize == nil && options.wordSize == nil)
            #expect(options.solidBlockSize == nil)
            #expect(options.password.isEmpty && options.encryption == .aes256 && !options.encryptFileNames)
            #expect(options.volumeSize == nil)
            #expect(!options.excludeDSStore, ".DS_Store stays in unless asked, as in Finder's Compress")
            #expect(options.canSave)
        }

        @Test func eachFormatKeepsItsOwnSettings() {
            let options = ArchiveSaveOptions(defaults: isolatedDefaults())
            options.method = .lzma
            options.level = 9
            options.dictionarySize = 1 << 20
            options.encryption = .zipCrypto
            options.password = "shared"
            options.passwordConfirmation = "shared"

            options.format = .sevenZ
            #expect(options.level == 5 && options.method == nil, "7z starts from its own defaults")
            #expect(options.password == "shared", "the password belongs to the save, not the format")
            options.method = .ppmd
            options.wordSize = 16
            options.encryptFileNames = true
            options.solidBlockSize = 0

            options.format = .zip
            #expect(options.method == .lzma && options.level == 9 && options.dictionarySize == 1 << 20)
            #expect(options.encryption == .zipCrypto)
            #expect(!options.encryptFileNames && options.solidBlockSize == nil, "zip has neither")

            options.format = .sevenZ
            #expect(options.method == .ppmd && options.wordSize == 16)
            #expect(options.encryptFileNames && options.solidBlockSize == 0)
        }

        @Test func aNewMethodDropsSettingsItDoesNotOffer() {
            let options = ArchiveSaveOptions(defaults: isolatedDefaults())
            options.format = .sevenZ
            options.method = .lzma2
            options.dictionarySize = 64 << 10
            options.wordSize = 273
            options.method = .bzip2
            #expect(options.dictionarySize == nil, "BZip2 has no 64 KB dictionary")
            #expect(options.wordSize == nil, "BZip2 has no word size")
            options.method = .lzma
            options.dictionarySize = 16 << 20
            options.method = .lzma2
            #expect(options.dictionarySize == 16 << 20, "LZMA2 offers the same dictionaries")
        }

        @Test func storeHandsTheWriterNoCodecSettings() throws {
            let options = ArchiveSaveOptions(defaults: isolatedDefaults())
            options.format = .sevenZ
            options.method = .ppmd
            options.dictionarySize = 16 << 20
            options.wordSize = 8
            options.solidBlockSize = 16 << 20
            options.level = 0
            let written = try #require(options.compressionOptions)
            #expect(written.method == nil && written.dictionarySize == nil && written.wordSize == nil)
            #expect(written.solidBlockSize == nil && written.solidMode == nil)

            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let url = dir.appendingPathComponent("store.7z")
            try SevenZipArchive.writeArchive(
                destination: url, items: [.addData(archivePath: "a.txt", data: sampleText(bytes: 20_000))],
                options: written)
            #expect(try recordedMethod(of: url).name == "Copy")
        }

        /// The writer holds the same line on its own: at level 0 a dictionary or
        /// word size is dropped, not passed on for 7-Zip to refuse.
        @Test(arguments: CompressionOptions.Format.allCases)
        func theWriterStoresWhateverCodecSettingsCome(_ format: CompressionOptions.Format) throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let url = dir.appendingPathComponent("store.\(format.rawValue)")
            try SevenZipArchive.writeArchive(
                destination: url, items: [.addData(archivePath: "a.txt", data: sampleText(bytes: 20_000))],
                options: .init(format: format, level: 0, method: .lzma, dictionarySize: 1 << 20, wordSize: 64))
            #expect(try recordedMethod(of: url).name == (format == .zip ? "Store" : "Copy"))
        }

        @Test func settingsSurviveARelaunch() {
            let defaults = isolatedDefaults()
            let first = ArchiveSaveOptions(defaults: defaults)
            first.format = .sevenZ
            first.level = 9
            first.method = .lzma
            first.dictionarySize = 64 << 20
            first.wordSize = 64
            first.solidBlockSize = 16 << 20
            first.encryptFileNames = true
            first.excludeDSStore = true
            first.volumeSize = 25 << 20
            first.password = "hunter2"
            first.passwordConfirmation = "hunter2"
            first.remember()

            let second = ArchiveSaveOptions(defaults: defaults)
            #expect(second.format == .sevenZ, "opens on the format used last")
            #expect(second.level == 9 && second.method == .lzma)
            #expect(second.dictionarySize == 64 << 20 && second.wordSize == 64 && second.solidBlockSize == 16 << 20)
            #expect(second.encryptFileNames && second.excludeDSStore)
            #expect(second.volumeSize == nil, "the volume size is a one-off")
            #expect(second.password.isEmpty && second.passwordConfirmation.isEmpty, "the password is never stored")
        }

        @Test func thePasswordNeverReachesTheStore() {
            let defaults = isolatedDefaults()
            let options = ArchiveSaveOptions(defaults: defaults)
            options.password = "correct horse battery staple"
            options.passwordConfirmation = options.password
            for format in CompressionOptions.Format.allCases {
                options.format = format
                options.remember()
            }
            var stored = ""
            for (_, value) in defaults.dictionaryRepresentation() {
                stored += (value as? Data).map { String(decoding: $0, as: UTF8.self) } ?? String(describing: value)
            }
            #expect(stored.contains("lzma2") || stored.contains("level"), "the settings themselves are stored")
            #expect(!stored.contains("correct horse"), "the password is not")
        }

        /// Quick Compress keeps its own settings, and keeps them at once: it has
        /// no Save button to wait for. Never the password or the volume size.
        @Test func quickCompressRemembersApartAndAtOnce() {
            let defaults = isolatedDefaults()
            let quick = ArchiveSaveOptions(defaults: defaults, storage: .quickCompress)
            quick.format = .sevenZ
            quick.level = 9
            quick.method = .ppmd
            quick.wordSize = 16
            quick.solidBlockSize = 0
            quick.encryptFileNames = true
            quick.excludeDSStore = true
            quick.password = "correct horse"
            quick.passwordConfirmation = "correct horse"
            quick.volumeSize = 25 << 20

            let again = ArchiveSaveOptions(defaults: defaults, storage: .quickCompress)
            #expect(again.format == .sevenZ && again.level == 9 && again.method == .ppmd)
            #expect(again.wordSize == 16 && again.solidBlockSize == 0 && again.encryptFileNames && again.excludeDSStore)
            #expect(again.password.isEmpty && again.volumeSize == nil, "never the password or the volume size")

            let panel = ArchiveSaveOptions(defaults: defaults)
            #expect(panel.format == .zip && panel.level == 5 && panel.method == nil && !panel.excludeDSStore,
                    "the save panel's settings are its own")
            var stored = ""
            for (_, value) in defaults.dictionaryRepresentation() {
                stored += (value as? Data).map { String(decoding: $0, as: UTF8.self) } ?? String(describing: value)
            }
            #expect(!stored.contains("correct horse"))
        }

        /// The save panel stores nothing until a save goes ahead.
        @Test func thePanelRemembersOnlyOnSave() {
            let defaults = isolatedDefaults()
            let panel = ArchiveSaveOptions(defaults: defaults)
            panel.format = .sevenZ
            panel.level = 9
            #expect(ArchiveSaveOptions(defaults: defaults).format == .zip)
            panel.remember()
            #expect(ArchiveSaveOptions(defaults: defaults).level == 9)
        }

        /// Before it had more options, Quick Compress kept one level for every
        /// format. That choice carries over, for every format.
        @Test func quickCompressKeepsTheLevelItHadBefore() {
            let defaults = isolatedDefaults()
            defaults.set(9, forKey: Keys.dropWindowLevel)
            defaults.set("7z", forKey: Keys.dropWindowFormat)
            let quick = ArchiveSaveOptions(defaults: defaults, storage: .quickCompress)
            #expect(quick.format == .sevenZ && quick.level == 9)
            quick.format = .zip
            #expect(quick.level == 9)
            quick.level = 1
            #expect(ArchiveSaveOptions(defaults: defaults, storage: .quickCompress).level == 1, "a new choice wins")
        }

        @Test func unreadableSettingsFallBackToTheDefaults() throws {
            let defaults = isolatedDefaults()
            defaults.set("rar", forKey: Keys.saveOptionsFormat)
            defaults.set(Data("not json".utf8), forKey: Keys.saveOptionsSettings("zip"))
            let nonsense = ArchiveSaveOptions.Remembered(
                level: 4, method: "lzma3", dictionarySize: 12_345, wordSize: 7,
                solidBlockSize: 3, encryption: "rot13", encryptFileNames: true)
            defaults.set(try JSONEncoder().encode(nonsense), forKey: Keys.saveOptionsSettings("7z"))

            let options = ArchiveSaveOptions(defaults: defaults)
            #expect(options.format == .zip, "an unknown format falls back to zip")
            #expect(options.level == 5 && options.method == nil)
            options.format = .sevenZ
            #expect(options.level == 5 && options.method == nil)
            #expect(options.dictionarySize == nil && options.wordSize == nil && options.solidBlockSize == nil)
            #expect(options.encryption == .aes256)
            #expect(options.encryptFileNames, "what is still valid is kept")
        }

        @Test func passwordProblemsAreNamed() {
            let options = ArchiveSaveOptions(defaults: isolatedDefaults())
            #expect(options.passwordProblem == nil)
            options.password = "abc"
            #expect(options.passwordProblem == .mismatch)
            #expect(!options.canSave)
            options.passwordConfirmation = "abc"
            #expect(options.passwordProblem == nil && options.canSave)

            options.password = "pässwörd"
            options.passwordConfirmation = "pässwörd"
            #expect(options.passwordProblem == .notASCII)
            options.format = .sevenZ
            #expect(options.passwordProblem == nil, "7z takes any password")

            options.format = .zip
            options.password = String(repeating: "a", count: 100)
            options.passwordConfirmation = options.password
            #expect(options.passwordProblem == .tooLong)
            options.encryption = .zipCrypto
            #expect(options.passwordProblem == nil, "ZipCrypto has no length limit")
        }

        /// A password with a problem hands the writer nothing, so no archive is
        /// ever locked behind a password nobody confirmed. Quick Compress has no
        /// Save button to hold it back: this is what does.
        @Test func noOptionsWhileThePasswordHasAProblem() {
            let options = ArchiveSaveOptions(defaults: isolatedDefaults(), storage: .quickCompress)
            #expect(options.compressionOptions != nil && options.compressionOptions?.password == nil)
            options.password = "secret"
            #expect(options.compressionOptions == nil, "typed once, not confirmed yet")
            options.passwordConfirmation = "secreT"
            #expect(options.compressionOptions == nil, "confirmed differently")
            options.passwordConfirmation = "secret"
            #expect(options.compressionOptions?.password == "secret")
            options.password = "pässwörd"
            options.passwordConfirmation = "pässwörd"
            #expect(options.compressionOptions == nil, "a zip cannot take it")
            options.format = .sevenZ
            #expect(options.compressionOptions?.password == "pässwörd", "a 7z can")
        }

        /// The start page's drop area shows only the format menu, so nothing else
        /// set for Quick Compress reaches it: no password, no volumes, the default
        /// level and codec.
        @Test func theStartPageTakesOnlyTheFormat() {
            let quick = ArchiveSaveOptions(defaults: isolatedDefaults(), storage: .quickCompress)
            quick.format = .sevenZ
            quick.level = 9
            quick.method = .ppmd
            quick.wordSize = 16
            quick.encryptFileNames = true
            quick.password = "secret"
            quick.passwordConfirmation = "secret"
            quick.volumeSize = 10 << 20
            let start = quick.startPageOptions
            #expect(start.format == .sevenZ)
            #expect(start.level == 5 && start.method == nil && start.wordSize == nil)
            #expect(start.password == nil && !start.encryptFileNames && start.volumeSize == nil)
        }

        @Test func theWriterGetsWhatWasSet() throws {
            let options = ArchiveSaveOptions(defaults: isolatedDefaults())
            options.format = .sevenZ
            options.level = 7
            options.method = .lzma2
            options.dictionarySize = 16 << 20
            options.wordSize = 64
            options.solidBlockSize = 0
            options.encryptFileNames = true
            options.password = "pw"
            options.passwordConfirmation = "pw"
            options.volumeSize = 100 << 20
            let o = try #require(options.compressionOptions)
            #expect(o.format == .sevenZ && o.level == 7 && o.method == .lzma2)
            #expect(o.dictionarySize == 16 << 20 && o.wordSize == 64)
            #expect(o.solidMode == false && o.solidBlockSize == nil, "0 means no solid blocks")
            #expect(o.encryptFileNames && o.password == "pw" && o.encryption == nil)
            #expect(o.volumeSize == 100 << 20)
            #expect(!o.excludeDSStore)
            options.excludeDSStore = true
            #expect(try #require(options.compressionOptions).excludeDSStore, "leaving .DS_Store out is one of the options")

            options.solidBlockSize = .max
            let solid = try #require(options.compressionOptions)
            #expect(solid.solidBlockSize == .max && solid.solidMode == nil)

            options.format = .zip
            let z = try #require(options.compressionOptions)
            #expect(z.solidMode == nil && z.solidBlockSize == nil && !z.encryptFileNames, "7z-only settings stay behind")
            #expect(z.encryption == .aes256 && z.password == "pw")
        }

        /// Every value the model offers the panel, one setting at a time, writes an
        /// archive that opens again — the lists and the writer cannot drift apart.
        @Test func everyValueThePanelOffersWrites() throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let data = sampleText(bytes: 50_000)
            let options = ArchiveSaveOptions(defaults: isolatedDefaults())
            var written = 0

            func write() throws {
                let url = dir.appendingPathComponent("\(UUID().uuidString).\(options.format.rawValue)")
                let o = try #require(options.compressionOptions)
                try SevenZipArchive.writeArchive(
                    destination: url, items: [.addData(archivePath: "a.txt", data: data)], options: o)
                let first = (o.volumeSize ?? 0) > 0 ? URL(fileURLWithPath: url.path + ".001") : url
                let out = dir.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
                try SevenZipArchive(url: first, password: o.password).extractAll(to: out)
                #expect(try Data(contentsOf: out.appendingPathComponent("a.txt")) == data,
                        "\(o.format.rawValue) level \(o.level) \(o.method?.rawValue ?? "-")")
                written += 1
            }

            for format in CompressionOptions.Format.allCases {
                options.format = format
                for method in [nil] + options.methods {
                    options.method = method
                    for level in options.levels {
                        options.level = level
                        try write()
                    }
                    options.level = 5
                    for size in options.dictionarySizes {
                        options.dictionarySize = size
                        try write()
                    }
                    options.dictionarySize = nil
                    for size in options.wordSizes {
                        options.wordSize = size
                        try write()
                    }
                    options.wordSize = nil
                }
                options.method = nil
                if options.hasSolidBlocks {
                    for size in [0] + options.solidBlockSizes {
                        options.solidBlockSize = size
                        try write()
                    }
                    options.solidBlockSize = nil
                }
                options.password = "pw"
                options.passwordConfirmation = "pw"
                for encryption in options.encryptions.isEmpty ? [.aes256] : options.encryptions {
                    options.encryption = encryption
                    for names in options.canEncryptFileNames ? [false, true] : [false] {
                        options.encryptFileNames = names
                        try write()
                    }
                }
                options.password = ""
                options.passwordConfirmation = ""
                options.encryptFileNames = false
                for size in options.volumeSizes {
                    options.volumeSize = size
                    try write()
                }
                options.volumeSize = nil
            }
            #expect(written > 150, "\(written) archives")
        }
    }

    // MARK: - .DS_Store

    struct DSStoreExclusionTests {

        @Test func onlyAddedFilesNamedExactlyDSStoreGo() {
            let disk = URL(fileURLWithPath: "/tmp/anything")
            let items: [ArchiveUpdateItem] = [
                .addFile(archivePath: ".DS_Store", diskPath: disk),
                .addFile(archivePath: "folder/.DS_Store", diskPath: disk),
                .addFile(archivePath: "a/b/c/.DS_Store", diskPath: disk),
                .addData(archivePath: "folder/.DS_Store", data: Data()),
                .addFile(archivePath: ".DS_Store.bak", diskPath: disk),
                .addFile(archivePath: "x.DS_Store", diskPath: disk),
                .addFile(archivePath: "DS_Store", diskPath: disk),
                .addFile(archivePath: ".ds_store", diskPath: disk),
                .addDirectory(archivePath: ".DS_Store", diskPath: disk),
                .remove(sourceIndex: 3),
                .move(sourceIndex: 4, newPath: "moved/.DS_Store"),
            ]
            let kept = items.excludingDSStore()
            let paths: [String] = kept.map { item in
                switch item {
                case .addFile(let path, _, _, _), .addData(let path, _, _, _), .addDirectory(let path, _, _, _): path
                case .remove(let index): "remove \(index)"
                case .move(let index, let path): "move \(index) \(path)"
                }
            }
            #expect(paths == [".DS_Store.bak", "x.DS_Store", "DS_Store", ".ds_store", ".DS_Store",
                              "remove 3", "move 4 moved/.DS_Store"])
        }

        /// A folder the way Finder leaves it: a `.DS_Store` in each level, one of
        /// them with metadata of its own that would earn it a sidecar.
        private func finderFolder(in dir: URL) throws -> URL {
            let fm = FileManager.default
            let folder = dir.appendingPathComponent("Photos")
            try fm.createDirectory(at: folder.appendingPathComponent("sub/deeper"), withIntermediateDirectories: true)
            try fm.createDirectory(at: folder.appendingPathComponent("onlyds"), withIntermediateDirectories: true)
            try "jpeg".write(to: folder.appendingPathComponent("a.jpg"), atomically: true, encoding: .utf8)
            try "keep".write(to: folder.appendingPathComponent(".DS_Store.bak"), atomically: true, encoding: .utf8)
            for path in [".DS_Store", "sub/.DS_Store", "sub/deeper/.DS_Store", "onlyds/.DS_Store"] {
                try Data("Bud1".utf8).write(to: folder.appendingPathComponent(path))
            }
            setExtendedAttribute("com.macpacker.test", Data("finder".utf8), at: folder.appendingPathComponent(".DS_Store"))
            return folder
        }

        @MainActor @Test(arguments: CompressionOptions.Format.allCases)
        func newArchivesLeaveDSStoreOutOnlyWhenAsked(_ format: CompressionOptions.Format) async throws {
            for exclude in [false, true] {
                let dir = try makeTempDir()
                defer { try? FileManager.default.removeItem(at: dir) }
                let folder = try finderFolder(in: dir)

                let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
                state.create()
                state.add(url: folder)
                let target = dir.appendingPathComponent("out.\(format.rawValue)")
                await state.save(to: target, options: .init(format: format, excludeDSStore: exclude))?.value
                #expect(state.error == nil, "\(state.error ?? "")")

                let paths = try storedPaths(target)
                let names = paths.map { ($0 as NSString).lastPathComponent }
                let dsStores = paths.filter { ($0 as NSString).lastPathComponent == ".DS_Store" }
                if exclude {
                    #expect(dsStores.isEmpty, "\(dsStores)")
                    #expect(!names.contains("._.DS_Store"), "no sidecar for a file left out: \(paths)")
                    #expect(!state.entries.values.contains { $0.name == ".DS_Store" }, "the window shows the file as saved")
                } else {
                    #expect(dsStores.count == 4, "every level's .DS_Store goes in when not excluded: \(dsStores)")
                    if format == .zip {
                        #expect(names.contains("._.DS_Store"), "its metadata goes in too, as a sidecar: \(paths)")
                    }
                }
                #expect(paths.contains("Photos/.DS_Store.bak"), "only the exact name counts")
                #expect(paths.contains("Photos/a.jpg"))
                #expect(paths.contains { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "Photos/onlyds" },
                        "a folder that held only a .DS_Store is still archived: \(paths)")
            }
        }

        /// An edit adds nothing Finder-made, and takes nothing the archive already
        /// holds: removing entries is a job for the user, not for a save option.
        @MainActor @Test func excludingKeepsWhatTheArchiveAlreadyHolds() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let zip = dir.appendingPathComponent("existing.zip")
            try SevenZipArchive.writeArchive(
                destination: zip,
                items: [.addData(archivePath: ".DS_Store", data: Data("Bud1".utf8)),
                        .addData(archivePath: "a.txt", data: Data("a".utf8))],
                options: .init(format: .zip))
            let folder = try finderFolder(in: dir)

            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.open(url: zip)
            try await state.openTask?.value
            state.add(url: folder)
            await state.save(options: .init(format: .zip, excludeDSStore: true))?.value
            #expect(state.error == nil, "\(state.error ?? "")")

            let paths = try systemZipEntries(zip)
            #expect(paths.contains(".DS_Store"), "the one the archive held stays")
            #expect(!paths.contains { $0.hasPrefix("Photos") && $0.hasSuffix(".DS_Store") }, "\(paths)")
            #expect(paths.contains("Photos/a.jpg"))
        }
    }

    // MARK: - Save As through the window

    @MainActor struct SaveAsStateTests {

        private func encryptedZip(in dir: URL) throws -> URL {
            let source = dir.appendingPathComponent("locked.zip")
            try FileManager.default.copyItem(at: passwordFixture("zip_aes256.zip"), to: source)
            return source
        }

        /// A 7z whose names take the password too: "password" opens it.
        private func hiddenNames7z(in dir: URL) throws -> URL {
            let source = dir.appendingPathComponent("hidden.7z")
            try FileManager.default.copyItem(at: passwordFixture("7z_encrypted_header.7z"), to: source)
            return source
        }

        private func makeState(_ prompts: Prompts) -> ArchiveState {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.passwordProvider = { _ in prompts.next() }
            state.folderAccessProvider = { _ in true }
            return state
        }

        private func opens(_ archive: URL, with password: String) throws -> Bool {
            let out = archive.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            do {
                try SevenZipArchive(url: archive, password: password).extractAll(to: out)
                return true
            } catch {
                return false
            }
        }

        @Test func saveAsAsksForTheSourcePasswordOnce() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let prompts = Prompts(["password"])
            let state = makeState(prompts)
            state.open(url: try encryptedZip(in: dir))
            try await state.openTask?.value

            let saved = dir.appendingPathComponent("fresh.7z")
            await state.save(to: saved, options: .init(format: .sevenZ, password: "fresh"))?.value
            #expect(state.error == nil, "\(state.error ?? "")")
            #expect(prompts.count == 1)
            #expect(try opens(saved, with: "fresh"))
            #expect(try !opens(saved, with: "password"))
            #expect(state.url == saved)
        }

        @Test func aWrongAnswerIsAskedAgain() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let prompts = Prompts(["nope", "password"])
            let state = makeState(prompts)
            state.open(url: try encryptedZip(in: dir))
            try await state.openTask?.value

            let saved = dir.appendingPathComponent("fresh.zip")
            await state.save(to: saved, options: .init(format: .zip, password: "fresh"))?.value
            #expect(state.error == nil, "\(state.error ?? "")")
            #expect(prompts.count == 2)
            #expect(try opens(saved, with: "fresh"))
        }

        /// A wrong answer is asked for again, but not without end: after the
        /// last one the save gives up, says why, and writes nothing.
        @Test func theSourcePasswordIsAskedForAFewTimesAtMost() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let prompts = Prompts(["nope"])
            let state = makeState(prompts)
            state.open(url: try encryptedZip(in: dir))
            try await state.openTask?.value

            let saved = dir.appendingPathComponent("fresh.zip")
            await state.save(to: saved, options: .init(format: .zip, password: "fresh"))?.value
            #expect(prompts.count == ArchiveSaver.passwordPrompts)
            #expect(state.saveError != nil)
            #expect(!FileManager.default.fileExists(atPath: saved.path))
        }

        @Test func cancellingThePromptLeavesNothingBehind() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let prompts = Prompts([nil])
            let state = makeState(prompts)
            state.open(url: try encryptedZip(in: dir))
            try await state.openTask?.value

            let saved = dir.appendingPathComponent("fresh.7z")
            await state.save(to: saved, options: .init(format: .sevenZ, password: "fresh"))?.value
            #expect(state.error != nil)
            #expect(prompts.count == 1)
            #expect(!FileManager.default.fileExists(atPath: saved.path))
        }

        /// A 7z with encrypted names asks when it is opened; the save uses that answer.
        @Test func aPasswordGivenWhenOpeningIsNotAskedForAgain() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let source = dir.appendingPathComponent("hidden.7z")
            try FileManager.default.copyItem(at: passwordFixture("7z_encrypted_header.7z"), to: source)
            let prompts = Prompts(["password"])
            let state = makeState(prompts)
            state.open(url: source)
            try await state.openTask?.value
            #expect(prompts.count == 1, "opening asked")

            let saved = dir.appendingPathComponent("fresh.zip")
            await state.save(to: saved, options: .init(format: .zip, password: "fresh"))?.value
            #expect(state.error == nil, "\(state.error ?? "")")
            #expect(prompts.count == 1, "saving did not ask again")
            #expect(try opens(saved, with: "fresh"))
        }

        /// Without a password for the copy: the same format copies the archive as it
        /// is, still encrypted, and another format is refused — never a plain copy.
        @Test func withoutANewPasswordAnEncryptedArchiveStaysEncrypted() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let prompts = Prompts([])
            let state = makeState(prompts)
            state.open(url: try encryptedZip(in: dir))
            try await state.openTask?.value

            let same = dir.appendingPathComponent("copy.zip")
            await state.save(to: same, options: .init(format: .zip))?.value
            #expect(state.error == nil, "\(state.error ?? "")")
            #expect(try SevenZipArchive(url: same).entries.filter { !$0.isDirectory && $0.size > 0 }.allSatisfy(\.isEncrypted))

            let other = dir.appendingPathComponent("copy.7z")
            await state.save(to: other, options: .init(format: .sevenZ))?.value
            #expect(state.error?.contains("password") == true, "\(state.error ?? "no error")")
            #expect(!FileManager.default.fileExists(atPath: other.path))
            #expect(prompts.count == 0, "nothing needed asking")
        }

        /// A 7z whose names are encrypted saves like any other: Save takes an added
        /// file, and a Save As without a new password copies it. Either way it
        /// stays locked as before, the added file too. The write opens the archive
        /// again, which takes its password: the one given when the window opened
        /// it, not asked for a second time.
        @Test(arguments: [false, true])
        func anArchiveWithHiddenNamesSaves(asACopy: Bool) async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let source = try hiddenNames7z(in: dir)
            let prompts = Prompts(["password"])
            let state = makeState(prompts)
            state.open(url: source)
            try await state.openTask?.value
            let added = dir.appendingPathComponent("added.txt")
            try "added".write(to: added, atomically: true, encoding: .utf8)
            state.add(url: added)

            let saved = asACopy ? dir.appendingPathComponent("copy.7z") : source
            await state.save(to: asACopy ? saved : nil, options: asACopy ? .init(format: .sevenZ) : nil)?.value
            #expect(state.error == nil, "\(state.error ?? "")")
            #expect(prompts.count == 1, "the password given when opening was asked for again")
            #expect(throws: (any Error).self, "its names open without the password") {
                _ = try SevenZipArchive(url: saved)
            }
            let files = try SevenZipArchive(url: saved, password: "password").entries
                .filter { !$0.isDirectory && $0.size > 0 }
            #expect(files.contains { $0.path == "hello world.txt" })
            #expect(files.contains { $0.path == "added.txt" })
            let plain = files.filter { !$0.isEncrypted }.map(\.path)
            #expect(plain.isEmpty, "left in plain: \(plain)")
            #expect(try opens(saved, with: "password"))
        }

        /// A refused or failed save leaves its reason for the window to show until
        /// it is dismissed; a save that goes through leaves none.
        @Test func aFailedSaveKeepsItsReasonUntilDismissed() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let state = makeState(Prompts([]))
            state.open(url: try encryptedZip(in: dir))
            try await state.openTask?.value

            await state.save(to: dir.appendingPathComponent("copy.7z"), options: .init(format: .sevenZ))?.value
            #expect(state.saveError?.contains("without a password") == true, "\(state.saveError ?? "no reason")")
            state.clearSaveError()
            #expect(state.saveError == nil)

            await state.save(to: dir.appendingPathComponent("copy.zip"), options: .init(format: .zip))?.value
            #expect(state.saveError == nil, "\(state.saveError ?? "")")

            // a reason belongs to the archive it was given for: opening another drops it
            await state.save(to: dir.appendingPathComponent("again.7z"), options: .init(format: .sevenZ))?.value
            #expect(state.saveError != nil)
            state.open(url: try makeSystemZipFixture(in: dir))
            #expect(state.saveError == nil)
        }

        /// A set of four 64 KB volumes written through the window, which then
        /// holds it. Noise, since anything that compresses would fit in one.
        private func splitSet(_ format: CompressionOptions.Format, in dir: URL) async throws -> ArchiveState {
            let file = dir.appendingPathComponent("noise.bin")
            try noise(bytes: 200_000).write(to: file)
            let state = makeState(Prompts([]))
            state.create()
            state.add(url: file)
            await state.save(to: dir.appendingPathComponent("set.\(format.rawValue)"),
                             options: .init(format: format, volumeSize: 64 << 10))?.value
            return state
        }

        @Test(arguments: CompressionOptions.Format.allCases)
        func aSplitSaveReopensItsFirstVolume(_ format: CompressionOptions.Format) async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let state = try await splitSet(format, in: dir)
            #expect(state.error == nil, "\(state.error ?? "")")
            #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("set.\(format.rawValue).004").path))
            #expect(state.url?.lastPathComponent == "set.\(format.rawValue).001")
            #expect(state.name == "set.\(format.rawValue)", "the window names the set, in the format's extension")
            #expect(state.entries.values.contains { $0.name == "noise.bin" })
        }

        /// The kinds of set a window can hold.
        enum VolumeSet: String, CaseIterable, Sendable {
            /// 7-Zip's numbered volumes, written through the window.
            case sevenZ, zip
            /// Info-ZIP's `zip -s`: split_pk.z01, split_pk.z02, split_pk.zip.
            case spanned
        }

        /// A set of volumes is not changed in place — 7-Zip does not update one
        /// either. Save says so and leaves every volume as it was; the change stays
        /// pending, for a Save As to write elsewhere.
        @Test(arguments: VolumeSet.allCases)
        func aSplitSetIsNotChangedInPlace(_ kind: VolumeSet) async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let state: ArchiveState
            switch kind {
            case .sevenZ: state = try await splitSet(.sevenZ, in: dir)
            case .zip: state = try await splitSet(.zip, in: dir)
            case .spanned:
                let fixtures = Bundle.module.url(forResource: "zip", withExtension: nil)!
                for part in ["split_pk.z01", "split_pk.z02", "split_pk.zip"] {
                    try FileManager.default.copyItem(at: fixtures.appendingPathComponent(part),
                                                     to: dir.appendingPathComponent(part))
                }
                state = makeState(Prompts([]))
                state.open(url: dir.appendingPathComponent("split_pk.zip"))
                try await state.openTask?.value
            }
            #expect(state.error == nil, "\(state.error ?? "")")
            let volumes = {
                try FileManager.default.contentsOfDirectory(atPath: dir.path)
                    .filter { $0 != "noise.bin" && $0 != "added.txt" }.sorted()
            }
            let names = try volumes()
            #expect(names.count >= 3, "\(names)")
            let before = try names.map { try Data(contentsOf: dir.appendingPathComponent($0)) }
            let added = dir.appendingPathComponent("added.txt")
            try "added".write(to: added, atomically: true, encoding: .utf8)
            state.add(url: added)

            await state.save()?.value
            #expect(state.saveError?.contains("Save As") == true, "\(state.saveError ?? "no reason")")
            #expect(state.hasPendingChanges, "the change is gone")
            #expect(try volumes() == names)
            #expect(try names.map { try Data(contentsOf: dir.appendingPathComponent($0)) } == before, "a volume changed")

            // and what it says to do works: Save As writes the set, change included, as one archive
            let format: CompressionOptions.Format = kind == .sevenZ ? .sevenZ : .zip
            let joined = dir.appendingPathComponent("joined.\(format.rawValue)")
            await state.save(to: joined, options: .init(format: format))?.value
            #expect(state.error == nil, "\(state.error ?? "")")
            #expect(try SevenZipArchive(url: joined).entries.contains { $0.path == "added.txt" })
        }

        /// The window reopens what it saved. With encrypted names that needs the
        /// password — the one typed for the save, not a second prompt.
        @Test func anEncryptedSaveReopensWithoutAsking() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let file = dir.appendingPathComponent("note.txt")
            try "secret note".write(to: file, atomically: true, encoding: .utf8)
            let prompts = Prompts([nil])
            let state = makeState(prompts)
            state.create()
            state.add(url: file)
            let target = dir.appendingPathComponent("hidden.7z")
            await state.save(to: target, options: .init(format: .sevenZ, password: "pw", encryptFileNames: true))?.value
            #expect(state.error == nil, "\(state.error ?? "")")
            #expect(prompts.count == 0, "the password was just given")
            #expect(state.entries.values.contains { $0.name == "note.txt" })
        }

        /// A zip whose one file Deflate shrinks, so its method shows: 7-Zip stores
        /// what a method would not shrink, and `zipinfo` then says `stor`.
        private func compressibleZip(in dir: URL) throws -> URL {
            let zip = dir.appendingPathComponent("text.zip")
            try SevenZipArchive.writeArchive(
                destination: zip,
                items: [.addData(archivePath: "text.txt",
                                 data: Data(String(repeating: "text text text\n", count: 200).utf8))],
                options: .init(format: .zip))
            return zip
        }

        /// Every entry is written again with the chosen method — onto another file,
        /// and onto the archive's own, where the panel suggests saving.
        @Test(arguments: [false, true])
        func saveAsCarriesTheChosenMethod(ontoItsOwnFile: Bool) async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let zip = try compressibleZip(in: dir)
            #expect(try zipMethods(zip)["text.txt"] == "defN")
            let state = makeState(Prompts([]))
            state.open(url: zip)
            try await state.openTask?.value

            let saved = ontoItsOwnFile ? zip : dir.appendingPathComponent("lzma.zip")
            await state.save(to: saved, options: .init(format: .zip, level: 9, method: .lzma))?.value
            #expect(state.error == nil, "\(state.error ?? "")")
            #expect(try zipMethods(saved)["text.txt"] == "lzma")
        }

        /// What locks an archive before it is saved again.
        enum Lock: String, CaseIterable, Sendable {
            /// A zip nothing locks.
            case none
            /// A zip whose contents take the password; its names do not.
            case contents
            /// A 7z whose names take the password too.
            case everything
        }

        /// Save As onto the archive's own file — what the panel suggests, as it
        /// opens in the archive's folder under its name — is a Save As all the
        /// same: the new password locks every entry, not only the ones added, and
        /// the old one opens nothing any more. The old password is asked for once:
        /// when the archive is opened, or when the save first needs it.
        @Test(arguments: Lock.allCases, [false, true])
        func saveAsOntoItsOwnFileEncryptsEveryEntry(_ lock: Lock, withAnAddition: Bool) async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let archive: URL
            switch lock {
            case .none: archive = try makeSystemZipFixture(in: dir)
            case .contents: archive = try encryptedZip(in: dir)
            case .everything: archive = try hiddenNames7z(in: dir)
            }
            let format: CompressionOptions.Format = lock == .everything ? .sevenZ : .zip
            let prompts = Prompts(["password"])
            let state = makeState(prompts)
            state.open(url: archive)
            try await state.openTask?.value
            if withAnAddition {
                let added = dir.appendingPathComponent("added.txt")
                try "added".write(to: added, atomically: true, encoding: .utf8)
                state.add(url: added)
            }

            await state.save(to: archive, options: .init(format: format, password: "fresh",
                                                         encryptFileNames: format == .sevenZ))?.value
            #expect(state.error == nil, "\(state.error ?? "")")
            #expect(prompts.count == (lock == .none ? 0 : 1))
            let files = try SevenZipArchive(url: archive, password: "fresh").entries
                .filter { !$0.isDirectory && $0.size > 0 }
            #expect(!files.isEmpty)
            #expect(files.contains { $0.path == "added.txt" } == withAnAddition)
            let plain = files.filter { !$0.isEncrypted }.map(\.path)
            #expect(plain.isEmpty, "left in plain: \(plain)")
            #expect(try opens(archive, with: "fresh"))
            if lock != .none {
                #expect(try !opens(archive, with: "password"), "the old password still opens it")
            }
            if format == .sevenZ {
                #expect(throws: (any Error).self, "its names open without the password") {
                    _ = try SevenZipArchive(url: archive)
                }
            }
        }
    }
}
