//
//  SaveOptionsWriteTests.swift
//  Modules
//
//  The writer's end of every option the save panel offers beyond format, method
//  and level: passwords, the codec settings, solid blocks, volumes. Each option
//  is checked for its effect in the archive, not just for being accepted, and
//  read back by an engine other than the one that wrote it wherever one can.
//

import Testing
import Foundation
import Swift7zip
@testable import Core

// MARK: - Helpers

/// Homebrew's 7-Zip, when installed: the one reader outside this code base that
/// understands every format and cipher written here. Tests use it when it is
/// there and are complete without it.
private let sevenZipTool = ["/opt/homebrew/bin/7zz", "/usr/local/bin/7zz"]
    .first { FileManager.default.isExecutableFile(atPath: $0) }

/// Runs `7zz`. It decodes its arguments by the locale, which a test process need
/// not have; without UTF-8 a Unicode password reaches it mangled.
@discardableResult
private func sevenZip(_ tool: String, _ args: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = args
    var environment = ProcessInfo.processInfo.environment
    environment["LC_ALL"] = "en_US.UTF-8"
    environment["LANG"] = "en_US.UTF-8"
    process.environment = environment
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    #expect(process.terminationStatus == 0, "7zz \(args.joined(separator: " ")): \(output)")
    return output
}

/// Lowercase letters at random: compressible, but with contexts enough to fill
/// any PPMd model — the sample text's sixteen words never do, and then the
/// model's memory changes nothing.
private func letters(bytes: Int) -> Data {
    var seed: UInt64 = 13
    return Data((0..<bytes).map { _ in
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let pick = seed >> 59   // 0...31
        return pick < 26 ? UInt8(97 + pick) : 32
    })
}

/// Expects `body` to throw the `SevenZipError` case named `expected`.
private func expectError(
    _ expected: String,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ body: () throws -> Void
) {
    do {
        try body()
        Issue.record("expected \(expected), but nothing was thrown", sourceLocation: sourceLocation)
    } catch let error as SevenZipError {
        #expect(String(describing: error).hasPrefix(expected), "got \(error)", sourceLocation: sourceLocation)
    } catch {
        Issue.record("expected \(expected), got \(error)", sourceLocation: sourceLocation)
    }
}

/// What the independent `zipinfo -v` says about every entry that holds data.
private func zipEntryDetails(_ zip: URL) throws -> [(size: Int, encrypted: Bool, method: String)] {
    func value(_ key: String, in block: Substring) -> String? {
        block.split(separator: "\n")
            .first { $0.trimmingCharacters(in: .whitespaces).hasPrefix(key) }
            .flatMap { $0.split(separator: ":", maxSplits: 1).last }
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
    let blocks = try run("/usr/bin/zipinfo", ["-v", zip.path])
        .components(separatedBy: "Central directory entry #").dropFirst()
    return blocks.compactMap { text -> (Int, Bool, String)? in
        let block = Substring(text)
        guard let sizeText = value("uncompressed size", in: block),
              let size = Int(sizeText.split(separator: " ").first ?? ""), size > 0 else { return nil }
        return (size, value("file security status", in: block) == "encrypted",
                value("compression method", in: block) ?? "")
    }
}

/// Deterministic, compressible text that differs by `seed`.
private func sampleText(bytes: Int, seed start: UInt64) -> Data {
    let words = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel",
                 "india", "juliet", "kilo", "lima", "mike", "november", "oscar", "papa"]
    var seed = start
    var text = ""
    while text.utf8.count < bytes {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        text += words[Int(seed >> 60)] + (seed & 7 == 0 ? "\n" : " ")
    }
    return Data(text.utf8)
}

/// Bytes no method can shrink, so volumes fill up predictably.
private func noise(bytes: Int) -> Data {
    var seed: UInt64 = 7
    return Data((0..<bytes).map { _ in
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return UInt8(truncatingIfNeeded: seed >> 56)
    })
}

/// The volumes `writeArchive` left next to `base`, in order.
private func volumes(of base: URL) throws -> [URL] {
    let prefix = base.lastPathComponent + "."
    return try FileManager.default.contentsOfDirectory(atPath: base.deletingLastPathComponent().path)
        .filter { $0.hasPrefix(prefix) && Int($0.dropFirst(prefix.count)) != nil }
        .sorted()
        .map { base.deletingLastPathComponent().appendingPathComponent($0) }
}

private func size(of url: URL) throws -> Int {
    try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? -1
}

// MARK: - Cases

/// One way the save panel can encrypt.
struct EncryptionCase: Sendable, CustomTestStringConvertible {
    let format: SevenZipCompressionOptions.Format
    let encryption: SevenZipCompressionOptions.Encryption?
    let encryptNames: Bool
    let method: SevenZipCompressionOptions.Method?
    let level: UInt32
    let password: String

    var testDescription: String {
        let cipher = format == .zip ? (encryption ?? .aes256).rawValue : (encryptNames ? "AES + names" : "AES")
        let how = level == 0 ? "store" : (method?.rawValue ?? "automatic")
        return "\(format.rawValue) · \(cipher) · \(how) · password of \(password.count) characters"
    }

    var options: SevenZipCompressionOptions {
        .init(format: format, level: level, method: method, password: password,
              encryption: encryption, encryptFileNames: encryptNames)
    }

    /// What 7-Zip's method string names the cipher.
    var cipherName: String {
        format == .zip ? (encryption == .zipCrypto ? "ZipCrypto" : "AES-256") : "7zAES"
    }

    /// Plain ASCII of every kind, and a password at AES's length limit. Zip
    /// takes nothing else; 7z takes any password, so it gets Unicode on top.
    static let zipPasswords = ["password", "p@ss w'ord\"$x", String(repeating: "a", count: 99)]
    static let sevenZipPasswords = zipPasswords + ["pässwörd✓", "密码 🔒 mit Leerzeichen"]

    static let all: [EncryptionCase] = {
        let hows: [(SevenZipCompressionOptions.Method?, UInt32)] = [(nil, 5), (.lzma, 5), (nil, 0)]
        let sevenZipHows: [(SevenZipCompressionOptions.Method?, UInt32)] = [(nil, 5), (.ppmd, 5), (nil, 0)]
        var cases: [EncryptionCase] = []
        for encryption in SevenZipCompressionOptions.Encryption.allCases {
            for (method, level) in hows {
                for password in zipPasswords {
                    cases.append(.init(format: .zip, encryption: encryption, encryptNames: false,
                                       method: method, level: level, password: password))
                }
            }
        }
        for names in [false, true] {
            for (method, level) in sevenZipHows {
                for password in sevenZipPasswords {
                    cases.append(.init(format: .sevenZ, encryption: nil, encryptNames: names,
                                       method: method, level: level, password: password))
                }
            }
        }
        return cases
    }()
}

/// A method in a format, for the settings that depend on both.
struct MethodCase: Sendable, CustomTestStringConvertible {
    let format: SevenZipCompressionOptions.Format
    let method: SevenZipCompressionOptions.Method?

    var testDescription: String { "\(format.rawValue) · \(method?.rawValue ?? "automatic")" }

    var effective: SevenZipCompressionOptions.Method {
        SevenZipCompressionOptions.effectiveMethod(method, in: format)
    }
    var dictionarySizes: [UInt64] { SevenZipCompressionOptions.dictionarySizes(for: format, method: method) }
    var wordSizes: [UInt32] { SevenZipCompressionOptions.wordSizes(for: format, method: method) }

    /// Big enough that the smallest dictionary on offer is smaller than it: at
    /// or above its size a dictionary is cut down to the data and changes
    /// nothing, and PPMd's smallest is 4 MB.
    var inputSize: Int { effective == .ppmd ? 6_000_000 : 320_000 }

    static let all: [MethodCase] = SevenZipCompressionOptions.Format.allCases.flatMap { format in
        ([nil] + SevenZipCompressionOptions.methods(for: format)).map { MethodCase(format: format, method: $0) }
    }
    static let withDictionary = all.filter { !$0.dictionarySizes.isEmpty }
    static let withWordSize = all.filter { !$0.wordSizes.isEmpty }
}

extension AllCoreTests {

    // MARK: - Encryption

    /// Every way to encrypt: the archive must need its password, name its cipher,
    /// and give its contents back to the right password — on both engines.
    struct EncryptionWriteTests {

        @Test(arguments: EncryptionCase.all)
        func encryptedArchivesNeedTheirPassword(_ c: EncryptionCase) async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let fm = FileManager.default
            let text = sampleText(bytes: 64_000, seed: 3)
            let inner = Data(String(repeating: "inner ", count: 200).utf8)
            let src = dir.appendingPathComponent("src")
            try fm.createDirectory(at: src.appendingPathComponent("folder"), withIntermediateDirectories: true)
            let textURL = src.appendingPathComponent("text.txt")
            try text.write(to: textURL)
            // a Finder tag gives the file a sidecar, which has to be encrypted too
            setExtendedAttribute("com.apple.metadata:_kMDItemUserTags", Data("tag".utf8), at: textURL)
            try inner.write(to: src.appendingPathComponent("folder/inner.txt"))
            try Data().write(to: src.appendingPathComponent("empty.txt"))

            let archive = dir.appendingPathComponent("out.\(c.format.rawValue)")
            try SevenZipArchive.writeArchive(
                destination: archive,
                items: [
                    .addFile(archivePath: "text.txt", diskPath: textURL),
                    .addDirectory(archivePath: "folder", diskPath: src.appendingPathComponent("folder")),
                    .addFile(archivePath: "folder/inner.txt", diskPath: src.appendingPathComponent("folder/inner.txt")),
                    .addFile(archivePath: "empty.txt", diskPath: src.appendingPathComponent("empty.txt")),
                ],
                options: c.options)

            // every file with contents is encrypted, and 7-Zip names the cipher
            let reader = try SevenZipArchive(url: archive, password: c.password)
            let files = try reader.entries.filter { !$0.isDirectory && $0.size > 0 }
            #expect(files.count == 2)
            for entry in files {
                let method = reader.method(ofEntryAt: entry.index) ?? "nothing"
                #expect(entry.isEncrypted, "\(entry.path) is not encrypted")
                #expect(method.contains(c.cipherName), "\(entry.path) recorded \(method)")
            }

            // with the password, both engines read it back — except XAD, which
            // cannot open a 7z whose names are encrypted
            for engine in ZipReader.allCases {
                let out = dir.appendingPathComponent("out-\(engine.rawValue)")
                if engine == .xad && c.encryptNames {
                    await #expect(throws: (any Error).self, "XAD opened a 7z with encrypted names") {
                        try await extractEverything(archive, with: engine, to: out, password: c.password)
                    }
                    continue
                }
                try await extractEverything(archive, with: engine, to: out, password: c.password)
                #expect(try Data(contentsOf: out.appendingPathComponent("text.txt")) == text, "through \(engine)")
                #expect(try Data(contentsOf: out.appendingPathComponent("folder/inner.txt")) == inner, "through \(engine)")
                let tag = extendedAttribute("com.apple.metadata:_kMDItemUserTags", at: out.appendingPathComponent("text.txt"))
                if engine == .xad {
                    // XAD hands back the contents of an encrypted archive, but not the
                    // Mac metadata in its encrypted sidecars. The 7-Zip engine does.
                    withKnownIssue("XAD does not restore Mac metadata from an encrypted archive (#246)") {
                        #expect(tag == Data("tag".utf8), "the Finder tag through \(engine)")
                    }
                } else {
                    #expect(tag == Data("tag".utf8), "the Finder tag through \(engine)")
                }
            }

            // without it: a zip and a 7z with plain names still list their names
            // but give nothing up; a 7z with encrypted names does not even open
            let out = dir.appendingPathComponent("out-none")
            try fm.createDirectory(at: out, withIntermediateDirectories: true)
            if c.encryptNames {
                expectError("passwordMissing") { _ = try SevenZipArchive(url: archive) }
                expectError("passwordWrong") { _ = try SevenZipArchive(url: archive, password: c.password + "x") }
            } else {
                let listing = try SevenZipArchive(url: archive)
                #expect(try listing.entries.contains { $0.path == "text.txt" }, "names stay readable")
                expectError("passwordMissing") { try listing.extractAll(to: out) }
                expectError("passwordWrong") {
                    try SevenZipArchive(url: archive, password: c.password + "x").extractAll(to: out)
                }
            }

            // zipinfo shares no code with 7-Zip: every entry with data is
            // encrypted, the sidecar included, and AES shows as method 99
            if c.format == .zip {
                let details = try zipEntryDetails(archive)
                #expect(details.count == 3, "text.txt, its sidecar and inner.txt: \(details)")
                #expect(details.allSatisfy { $0.encrypted }, "\(details)")
                if c.encryption != .zipCrypto {
                    #expect(details.allSatisfy { $0.method.contains("99") }, "AES is zip method 99: \(details)")
                }
                // Info-ZIP decrypts ZipCrypto over Deflate and Store
                if c.encryption == .zipCrypto && c.method == nil {
                    try run("/usr/bin/unzip", ["-tq", "-P", c.password, archive.path])
                }
            }

            // Foundation hands a process its arguments decomposed (NFD), so
            // "ä" would reach 7zz as "a" plus a combining umlaut — a different
            // password. Both engines above already read those archives.
            let decomposes = Array(c.password.utf8) != Array(c.password.decomposedStringWithCanonicalMapping.utf8)
            if let tool = sevenZipTool, !decomposes {
                try sevenZip(tool, ["t", "-p\(c.password)", archive.path])
            }
        }

        /// Zip keeps its password as plain ASCII — 7-Zip refuses anything else —
        /// and WinZip AES stops at 99 characters. Checked before the write, with
        /// a message that says so, instead of 7-Zip's bare failure.
        @Test func zipPasswordsFollow7ZipsRule() throws {
            let cases: [(String, SevenZipCompressionOptions.Encryption?, Bool)] = [
                ("password", nil, true),
                ("p@ss w'ord\"$x ~", .aes256, true),
                (String(repeating: "a", count: 99), .aes256, true),
                (String(repeating: "a", count: 100), .aes256, false),
                (String(repeating: "a", count: 200), .zipCrypto, true),
                ("pässwörd", .aes256, false),
                ("pässwörd", .zipCrypto, false),
                ("tab\there", nil, false),
                ("🔒", .zipCrypto, false),
            ]
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            for (index, (password, encryption, valid)) in cases.enumerated() {
                #expect(SevenZipCompressionOptions.isValidZipPassword(password, encryption: encryption) == valid,
                        "\(password.debugDescription) with \(encryption?.rawValue ?? "default")")
                let archive = dir.appendingPathComponent("case\(index).zip")
                let write = {
                    try SevenZipArchive.writeArchive(
                        destination: archive,
                        items: [.addData(archivePath: "a.txt", data: Data("a".utf8))],
                        options: .init(format: .zip, password: password, encryption: encryption))
                }
                if valid {
                    try write()
                } else {
                    expectError("writeFailed") { try write() }
                    #expect(!FileManager.default.fileExists(atPath: archive.path), "nothing may be left behind")
                }
            }
        }

        /// A 7z's password is any text at all.
        @Test func sevenZipTakesAnyPassword() throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            for password in ["pässwörd✓", "密码", "🔒🔑", String(repeating: "ü", count: 300), "tab\there"] {
                let archive = dir.appendingPathComponent("\(UUID().uuidString).7z")
                try SevenZipArchive.writeArchive(
                    destination: archive,
                    items: [.addData(archivePath: "a.txt", data: Data("secret".utf8))],
                    options: .init(format: .sevenZ, password: password, encryptFileNames: true))
                let out = dir.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
                try SevenZipArchive(url: archive, password: password).extractAll(to: out)
                #expect(try String(contentsOf: out.appendingPathComponent("a.txt"), encoding: .utf8) == "secret",
                        "\(password.debugDescription)")
            }
        }

        /// No password, or an empty one, writes no encryption at all.
        @Test(arguments: SevenZipCompressionOptions.Format.allCases)
        func anEmptyPasswordEncryptsNothing(_ format: SevenZipCompressionOptions.Format) throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            for password in [nil, ""] as [String?] {
                let archive = dir.appendingPathComponent("\(UUID().uuidString).\(format.rawValue)")
                try SevenZipArchive.writeArchive(
                    destination: archive,
                    items: [.addData(archivePath: "a.txt", data: sampleText(bytes: 10_000, seed: 1))],
                    options: .init(format: format, password: password, encryptFileNames: true))
                let reader = try SevenZipArchive(url: archive)
                #expect(try reader.entries.allSatisfy { !$0.isEncrypted })
            }
        }
    }

    // MARK: - Save As of an encrypted archive

    struct EncryptedSaveAsTests {

        private func encryptedSource(in dir: URL) throws -> URL {
            let source = dir.appendingPathComponent("source.zip")
            try FileManager.default.copyItem(at: passwordFixture("zip_aes256.zip"), to: source)
            return source
        }

        /// With a password for the copy, an encrypted archive is rebuilt like any
        /// other — read with its own password, written with the new one.
        @Test(arguments: [
            SevenZipCompressionOptions(format: .sevenZ, password: "fresh"),
            SevenZipCompressionOptions(format: .sevenZ, password: "fresh", encryptFileNames: true),
            SevenZipCompressionOptions(format: .zip, password: "fresh"),
            SevenZipCompressionOptions(format: .zip, password: "fresh", encryption: .zipCrypto),
        ])
        func saveAsReencryptsUnderTheNewPassword(_ options: SevenZipCompressionOptions) async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let source = try encryptedSource(in: dir)
            let original = dir.appendingPathComponent("original")
            try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
            try SevenZipArchive(url: source, password: "password").extractAll(to: original)

            let saved = dir.appendingPathComponent("saved.\(options.format.rawValue)")
            try SevenZipArchive.writeArchive(
                source: source, destination: saved, items: [], options: options, sourcePassword: "password")

            #expect(try archiveFormat(of: saved) == options.format.rawValue)
            let reader = try SevenZipArchive(url: saved, password: "fresh")
            #expect(try reader.entries.filter { !$0.isDirectory && $0.size > 0 }.allSatisfy(\.isEncrypted))
            // both engines read it back with the new password — except XAD, which
            // cannot open a 7z whose names are encrypted
            for engine in ZipReader.allCases {
                let out = dir.appendingPathComponent("out-\(engine.rawValue)")
                if engine == .xad && options.encryptFileNames {
                    await #expect(throws: (any Error).self, "XAD opened a 7z with encrypted names") {
                        try await extractEverything(saved, with: engine, to: out, password: "fresh")
                    }
                    continue
                }
                try await extractEverything(saved, with: engine, to: out, password: "fresh")
                for file in FileManager.default.subpaths(atPath: original.path) ?? [] {
                    var isDirectory: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: original.appendingPathComponent(file).path, isDirectory: &isDirectory),
                          !isDirectory.boolValue else { continue }
                    #expect(try Data(contentsOf: out.appendingPathComponent(file)) == Data(contentsOf: original.appendingPathComponent(file)),
                            "\(file) changed on the way, read back through \(engine)")
                }
            }
            // the old password no longer opens it
            let wrong = dir.appendingPathComponent("wrong")
            try FileManager.default.createDirectory(at: wrong, withIntermediateDirectories: true)
            if options.encryptFileNames {
                expectError("passwordWrong") { _ = try SevenZipArchive(url: saved, password: "password") }
            } else {
                expectError("passwordWrong") { try SevenZipArchive(url: saved, password: "password").extractAll(to: wrong) }
            }
        }

        @Test func saveAsOfAnEncryptedArchiveNeedsItsPassword() throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let source = try encryptedSource(in: dir)
            let saved = dir.appendingPathComponent("saved.7z")
            let options = SevenZipCompressionOptions(format: .sevenZ, password: "fresh")
            expectError("passwordMissing") {
                try SevenZipArchive.writeArchive(source: source, destination: saved, items: [], options: options)
            }
            expectError("passwordWrong") {
                try SevenZipArchive.writeArchive(source: source, destination: saved, items: [], options: options,
                                                 sourcePassword: "not it")
            }
            #expect(!FileManager.default.fileExists(atPath: saved.path), "nothing may be left behind")
        }
    }

    // MARK: - Dictionary, word size, solid blocks

    struct CodecSettingTests {

        private func write(_ c: MethodCase, dictionary: UInt64? = nil, word: UInt32? = nil,
                           input: URL, into dir: URL) throws -> URL {
            let url = dir.appendingPathComponent("\(UUID().uuidString).\(c.format.rawValue)")
            try SevenZipArchive.writeArchive(
                destination: url,
                items: [.addFile(archivePath: "input.txt", diskPath: input)],
                options: .init(format: c.format, method: c.method, dictionarySize: dictionary, wordSize: word))
            return url
        }

        private func input(for c: MethodCase, in dir: URL) throws -> (URL, Data) {
            let data = c.effective == .ppmd ? letters(bytes: c.inputSize) : sampleText(bytes: c.inputSize, seed: 11)
            let url = dir.appendingPathComponent("input.txt")
            try data.write(to: url)
            return (url, data)
        }

        /// What each engine the app reads with gets back out of `archive`.
        private func readBack(_ archive: URL, in dir: URL) async throws -> [(ZipReader, Data)] {
            var contents: [(ZipReader, Data)] = []
            for engine in ZipReader.allCases {
                let out = dir.appendingPathComponent(UUID().uuidString)
                try await extractEverything(archive, with: engine, to: out)
                contents.append((engine, try Data(contentsOf: out.appendingPathComponent("input.txt"))))
            }
            return contents
        }

        @Test(arguments: MethodCase.withDictionary)
        func everyOfferedDictionaryWorks(_ c: MethodCase) async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let (input, data) = try input(for: c, in: dir)
            var packed: [UInt64: UInt64] = [:]
            for size in c.dictionarySizes {
                let archive = try write(c, dictionary: size, input: input, into: dir)
                for (engine, read) in try await readBack(archive, in: dir) {
                    #expect(read == data, "\(size) bytes, read back through \(engine)")
                }
                packed[size] = try recordedMethod(of: archive).entry.packedSize
            }
            // the setting reaches the encoder: the smallest and the largest write
            // different bytes
            let smallest = packed[c.dictionarySizes.first!]!
            let largest = packed[c.dictionarySizes.last!]!
            #expect(smallest != largest, "every dictionary wrote \(smallest) bytes")
        }

        @Test(arguments: MethodCase.withWordSize)
        func everyOfferedWordSizeWorks(_ c: MethodCase) async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let (input, data) = try input(for: c, in: dir)
            var packed: [UInt32: UInt64] = [:]
            for word in c.wordSizes {
                let archive = try write(c, word: word, input: input, into: dir)
                for (engine, read) in try await readBack(archive, in: dir) {
                    #expect(read == data, "word size \(word), read back through \(engine)")
                }
                packed[word] = try recordedMethod(of: archive).entry.packedSize
            }
            #expect(packed[c.wordSizes.first!]! != packed[c.wordSizes.last!]!,
                    "every word size wrote \(packed[c.wordSizes.first!]!) bytes")
        }

        /// 7z writes down what it was given, so there the value itself is checked.
        @Test func sevenZipRecordsTheSettingsItWasGiven() throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let small = dir.appendingPathComponent("small.txt")
            try sampleText(bytes: 320_000, seed: 5).write(to: small)
            let big = dir.appendingPathComponent("big.txt")
            try sampleText(bytes: 6_000_000, seed: 5).write(to: big)
            func recorded(_ method: SevenZipCompressionOptions.Method, input: URL,
                          dictionary: UInt64? = nil, word: UInt32? = nil) throws -> String {
                let url = dir.appendingPathComponent("\(UUID().uuidString).7z")
                try SevenZipArchive.writeArchive(
                    destination: url, items: [.addFile(archivePath: "input.txt", diskPath: input)],
                    options: .init(format: .sevenZ, method: method, dictionarySize: dictionary, wordSize: word))
                return try recordedMethod(of: url).full
            }
            #expect(try recorded(.lzma2, input: small, dictionary: 64 << 10) == "LZMA2:16")
            #expect(try recorded(.lzma, input: small, dictionary: 64 << 10) == "LZMA:16")
            #expect(try recorded(.ppmd, input: big, dictionary: 4 << 20, word: 8) == "PPMD:o8:mem22")
            for order in SevenZipCompressionOptions.wordSizes(for: .sevenZ, method: .ppmd) {
                #expect(try recorded(.ppmd, input: small, word: order).split(separator: ":")[1] == "o\(order)")
            }
        }

        /// A setting the method does not have must fail loudly: dropped silently,
        /// the archive would come out other than the one asked for.
        @Test func aSettingTheMethodDoesNotHaveIsRefused() throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let items: [ArchiveUpdateItem] = [.addData(archivePath: "a.txt", data: sampleText(bytes: 10_000, seed: 2))]
            for (index, options) in [
                SevenZipCompressionOptions(format: .zip, method: .deflate, dictionarySize: 1 << 20),
                SevenZipCompressionOptions(format: .zip, method: .bzip2, wordSize: 64),
            ].enumerated() {
                let url = dir.appendingPathComponent("refused\(index).\(options.format.rawValue)")
                expectError("writeFailed") {
                    try SevenZipArchive.writeArchive(destination: url, items: items, options: options)
                }
                #expect(!FileManager.default.fileExists(atPath: url.path), "nothing may be left behind")
            }
        }

        /// A block is as many files as fit under the size; each block's first file
        /// carries the packed size of the whole block, the others none.
        @Test func solidBlocksFollowTheSetting() async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            var items: [ArchiveUpdateItem] = []
            var files: [String: Data] = [:]
            for (index, name) in ["a.txt", "b.txt", "c.txt"].enumerated() {
                let url = dir.appendingPathComponent(name)
                let data = sampleText(bytes: 400_000, seed: UInt64(index + 1))
                try data.write(to: url)
                files[name] = data
                items.append(.addFile(archivePath: name, diskPath: url))
            }
            func blocks(_ options: SevenZipCompressionOptions) async throws -> Int {
                let url = dir.appendingPathComponent("\(UUID().uuidString).7z")
                try SevenZipArchive.writeArchive(destination: url, items: items, options: options)
                // however the blocks fell, both engines read every file back
                for engine in ZipReader.allCases {
                    let out = dir.appendingPathComponent(UUID().uuidString)
                    try await extractEverything(url, with: engine, to: out)
                    for (name, data) in files {
                        #expect(try Data(contentsOf: out.appendingPathComponent(name)) == data, "\(name) through \(engine)")
                    }
                }
                return try SevenZipArchive(url: url).entries.filter { $0.packedSize > 0 }.count
            }
            #expect(try await blocks(.init(format: .sevenZ)) == 1, "7z is solid by default")
            #expect(try await blocks(.init(format: .sevenZ, solidMode: false)) == 3, "non-solid: a block per file")
            #expect(try await blocks(.init(format: .sevenZ, solidBlockSize: 1 << 20)) == 2, "1 MB holds two 400 KB files")
            for size in SevenZipCompressionOptions.solidBlockSizes.dropFirst() {
                #expect(try await blocks(.init(format: .sevenZ, solidBlockSize: size)) == 1, "\(size) bytes holds all three")
            }
        }
    }

    // MARK: - Volumes

    struct VolumeWriteTests {

        /// 250 KB that nothing shrinks, in 64 KB volumes: four of them, the first
        /// three exactly full.
        @MainActor @Test(arguments: SevenZipCompressionOptions.Format.allCases)
        func volumesSplitAtTheSizeAskedFor(_ format: SevenZipCompressionOptions.Format) async throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let payload = noise(bytes: 250_000)
            let input = dir.appendingPathComponent("noise.bin")
            try payload.write(to: input)
            let base = dir.appendingPathComponent("split.\(format.rawValue)")
            let volumeSize = 64 << 10
            try SevenZipArchive.writeArchive(
                destination: base, items: [.addFile(archivePath: "noise.bin", diskPath: input)],
                options: .init(format: format, volumeSize: UInt64(volumeSize)))

            let parts = try volumes(of: base)
            let sizes = try parts.map(size(of:))
            #expect(!FileManager.default.fileExists(atPath: base.path), "only the volumes are written")
            #expect(parts.map(\.lastPathComponent) == (1...parts.count).map { "split.\(format.rawValue).\(String(format: "%03d", $0))" })
            #expect(parts.count == (sizes.reduce(0, +) + volumeSize - 1) / volumeSize)
            #expect(parts.count == 4, "\(sizes)")
            #expect(sizes.dropLast().allSatisfy { $0 == volumeSize }, "\(sizes)")
            #expect((1...volumeSize).contains(sizes.last ?? 0), "\(sizes)")

            // the set opens from its first volume, through the bridge and through
            // the app's loader, which has to recognize it as a set
            let out = dir.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            try SevenZipArchive(url: parts[0]).extractAll(to: out)
            #expect(try Data(contentsOf: out.appendingPathComponent("noise.bin")) == payload)

            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.folderAccessProvider = { _ in true }   // the volumes beside it take folder access
            state.open(url: parts[0])
            try await state.openTask?.value
            let names = state.entries.values.compactMap(\.virtualPath)
            #expect(names.contains("noise.bin"), "\(names)")

            if let tool = sevenZipTool {
                try sevenZip(tool, ["t", parts[0].path])
            }

            // The volumes are the archive cut into pieces. Joined again, XAD reads
            // it, and a zip Info-ZIP too: neither shares code with 7-Zip. (The app
            // itself opens a set only with 7-Zip.)
            let joined = dir.appendingPathComponent("joined.\(format.rawValue)")
            try Data(try parts.map { try Data(contentsOf: $0) }.joined()).write(to: joined)
            let xadOut = dir.appendingPathComponent("out-xad")
            try await extractEverything(joined, with: .xad, to: xadOut)
            #expect(try Data(contentsOf: xadOut.appendingPathComponent("noise.bin")) == payload, "the joined volumes through XAD")
            if format == .zip {
                try run("/usr/bin/unzip", ["-tq", joined.path])
            }
        }

        @Test(arguments: SevenZipCompressionOptions.Format.allCases)
        func encryptedVolumesNeedThePassword(_ format: SevenZipCompressionOptions.Format) throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let payload = noise(bytes: 200_000)
            let input = dir.appendingPathComponent("noise.bin")
            try payload.write(to: input)
            let base = dir.appendingPathComponent("secret.\(format.rawValue)")
            try SevenZipArchive.writeArchive(
                destination: base, items: [.addFile(archivePath: "noise.bin", diskPath: input)],
                options: .init(format: format, password: "password", encryptFileNames: format == .sevenZ,
                               volumeSize: 64 << 10))
            let first = try #require(try volumes(of: base).first)
            let out = dir.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            try SevenZipArchive(url: first, password: "password").extractAll(to: out)
            #expect(try Data(contentsOf: out.appendingPathComponent("noise.bin")) == payload)
            if format == .sevenZ {
                expectError("passwordMissing") { _ = try SevenZipArchive(url: first) }
            } else {
                expectError("passwordMissing") { try SevenZipArchive(url: first).extractAll(to: out) }
            }
        }

        /// The smallest preset, for real: 25 MB of noise makes three 10 MB volumes.
        @Test func theSmallestPresetSplitsForReal() throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let preset = try #require(SevenZipCompressionOptions.volumeSizes.first)
            #expect(preset == 10 << 20)
            let payload = noise(bytes: 25_000_000)
            let input = dir.appendingPathComponent("noise.bin")
            try payload.write(to: input)
            let base = dir.appendingPathComponent("big.zip")
            try SevenZipArchive.writeArchive(
                destination: base, items: [.addFile(archivePath: "noise.bin", diskPath: input)],
                options: .init(format: .zip, volumeSize: preset))
            let sizes = try volumes(of: base).map(size(of:))
            #expect(sizes.count == 3, "\(sizes)")
            #expect(sizes.dropLast().allSatisfy { $0 == Int(preset) }, "\(sizes)")
            let out = dir.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            try SevenZipArchive(url: try #require(try volumes(of: base).first)).extractAll(to: out)
            #expect(try Data(contentsOf: out.appendingPathComponent("noise.bin")) == payload)
        }

        @Test func volumesAreNeverWrittenInPlace() throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let zip = dir.appendingPathComponent("a.zip")
            try SevenZipArchive.writeArchive(
                destination: zip, items: [.addData(archivePath: "a.txt", data: Data("a".utf8))],
                options: .init(format: .zip))
            expectError("writeFailed") {
                try SevenZipArchive.writeArchive(
                    source: zip, destination: zip, items: [.addData(archivePath: "b.txt", data: Data("b".utf8))],
                    options: .init(format: .zip, volumeSize: 1 << 20))
            }
            #expect(try volumes(of: zip).isEmpty)
        }

        /// A folder that cannot be written: the failure names the file it could not
        /// create — the app answers that by asking for folder access — and leaves no
        /// volume behind.
        @Test func aFailedVolumeWriteLeavesNothingBehind() throws {
            let dir = try makeTempDir()
            defer {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.appendingPathComponent("locked").path)
                try? FileManager.default.removeItem(at: dir)
            }
            let locked = dir.appendingPathComponent("locked")
            try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
            let base = locked.appendingPathComponent("split.zip")
            do {
                try SevenZipArchive.writeArchive(
                    destination: base, items: [.addData(archivePath: "noise.bin", data: noise(bytes: 200_000))],
                    options: .init(format: .zip, volumeSize: 64 << 10))
                Issue.record("wrote into a read-only folder")
            } catch SevenZipError.writeFailed(let message) {
                #expect(message.contains("Cannot create output file"), "\(message)")
            }
            #expect(try volumes(of: base).isEmpty)
        }
    }
}
