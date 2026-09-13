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
            let written = options.compressionOptions
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
        @Test(arguments: SevenZipCompressionOptions.Format.allCases)
        func theWriterStoresWhateverCodecSettingsCome(_ format: SevenZipCompressionOptions.Format) throws {
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
            for format in SevenZipCompressionOptions.Format.allCases {
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

        @Test func theWriterGetsWhatWasSet() {
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
            let o = options.compressionOptions
            #expect(o.format == .sevenZ && o.level == 7 && o.method == .lzma2)
            #expect(o.dictionarySize == 16 << 20 && o.wordSize == 64)
            #expect(o.solidMode == false && o.solidBlockSize == nil, "0 means no solid blocks")
            #expect(o.encryptFileNames && o.password == "pw" && o.encryption == nil)
            #expect(o.volumeSize == 100 << 20)

            options.solidBlockSize = .max
            #expect(options.compressionOptions.solidBlockSize == .max && options.compressionOptions.solidMode == nil)

            options.format = .zip
            let z = options.compressionOptions
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
                let o = options.compressionOptions
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

            for format in SevenZipCompressionOptions.Format.allCases {
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
            let kept = ArchiveState.excludingDSStore(items)
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

        @MainActor @Test(arguments: SevenZipCompressionOptions.Format.allCases)
        func newArchivesLeaveDSStoreOutOnlyWhenAsked(_ format: SevenZipCompressionOptions.Format) async throws {
            for exclude in [false, true] {
                let dir = try makeTempDir()
                defer { try? FileManager.default.removeItem(at: dir) }
                let folder = try finderFolder(in: dir)

                let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
                state.create()
                state.add(url: folder)
                let target = dir.appendingPathComponent("out.\(format.rawValue)")
                await state.save(to: target, options: .init(format: format), excludeDSStore: exclude)?.value
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
            await state.save(options: .init(format: .zip), excludeDSStore: true)?.value
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

        @Test(arguments: SevenZipCompressionOptions.Format.allCases)
        func aSplitSaveReopensItsFirstVolume(_ format: SevenZipCompressionOptions.Format) async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            var noise = Data(count: 200_000)
            for i in noise.indices { noise[i] = UInt8(truncatingIfNeeded: i &* 2654435761 >> 7) }
            let file = dir.appendingPathComponent("noise.bin")
            try noise.write(to: file)

            let state = makeState(Prompts([]))
            state.create()
            state.add(url: file)
            let target = dir.appendingPathComponent("set.\(format.rawValue)")
            await state.save(to: target, options: .init(format: format, volumeSize: 64 << 10))?.value
            #expect(state.error == nil, "\(state.error ?? "")")
            #expect(state.url?.lastPathComponent == "set.\(format.rawValue).001")
            #expect(state.name == "set.\(format.rawValue)", "the window names the set, in the format's extension")
            #expect(state.entries.values.contains { $0.name == "noise.bin" })
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

        @Test func saveAsCarriesTheChosenMethod() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let zip = try makeSystemZipFixture(in: dir)
            let state = makeState(Prompts([]))
            state.open(url: zip)
            try await state.openTask?.value
            let saved = dir.appendingPathComponent("lzma.zip")
            await state.save(to: saved, options: .init(format: .zip, level: 9, method: .lzma))?.value
            #expect(state.error == nil, "\(state.error ?? "")")
            #expect(try zipMethods(saved).values.filter { $0 != "stor" }.allSatisfy { $0 == "lzma" })
        }
    }
}
