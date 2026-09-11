//
//  ArchiveSaveOptions.swift
//  Modules
//
//  What the save panel asks for when an archive is written — format,
//  compression, password, volumes, the codec settings — and what it remembers
//  between saves.
//

import Combine
import Foundation
import Swift7zip

/// The save panel's options, and their memory.
///
/// Remembered the way 7-Zip does it: per format, so switching zip → 7z → zip
/// brings the zip settings back, and across launches. The password never is —
/// not between formats, not on disk — and neither is the volume size: both are
/// one-off choices that would otherwise follow the user into archives they
/// never meant to lock or split.
///
/// The save panel and Quick Compress each keep their own, in their own keys.
@MainActor
public final class ArchiveSaveOptions: ObservableObject {
    public typealias Format = SevenZipCompressionOptions.Format
    public typealias Method = SevenZipCompressionOptions.Method
    public typealias Encryption = SevenZipCompressionOptions.Encryption

    /// What is wrong with the password, for the panel to say.
    public enum PasswordProblem: Equatable, Sendable {
        /// The two fields differ.
        case mismatch
        /// A zip password can only be plain ASCII.
        case notASCII
        /// Longer than zip's AES takes.
        case tooLong
    }

    /// Where a set of options is kept, and when.
    public enum Storage: Sendable {
        /// Remembered when a save goes ahead.
        case savePanel
        /// Remembered as it changes: Quick Compress has no Save button to wait for.
        case quickCompress

        var formatKey: String { self == .savePanel ? Keys.saveOptionsFormat : Keys.dropWindowFormat }
        func settingsKey(_ format: Format) -> String {
            self == .savePanel ? Keys.saveOptionsSettings(format.rawValue) : Keys.dropWindowSettings(format.rawValue)
        }
        var excludeDSStoreKey: String { self == .savePanel ? Keys.saveOptionsExcludeDSStore : Keys.dropWindowExcludeDSStore }
        /// Quick Compress kept one level for every format before this.
        var legacyLevelKey: String? { self == .savePanel ? nil : Keys.dropWindowLevel }
    }

    @Published public var format: Format {
        didSet {
            guard oldValue != format else { return }
            remembered[oldValue] = snapshot()
            apply(remembered[format] ?? Remembered())
            autosave()
        }
    }
    @Published public var level: UInt32 = 5 { didSet { autosave() } }
    /// `nil` is the format's own choice: Deflate for zip, LZMA2 for 7z.
    @Published public var method: Method? = nil {
        didSet {
            if oldValue != method { dropWhatTheMethodLacks() }
            autosave()
        }
    }
    @Published public var dictionarySize: UInt64? = nil { didSet { autosave() } }
    @Published public var wordSize: UInt32? = nil { didSet { autosave() } }
    /// 7z only. `nil` leaves it to the level, 0 writes no solid blocks, `.max`
    /// one block for everything.
    @Published public var solidBlockSize: UInt64? = nil { didSet { autosave() } }
    @Published public var password = ""
    @Published public var passwordConfirmation = ""
    /// Zip only; 7z always uses AES-256.
    @Published public var encryption: Encryption = .aes256 { didSet { autosave() } }
    /// 7z only; a zip always lists its names.
    @Published public var encryptFileNames = false { didSet { autosave() } }
    /// `nil` writes one file.
    @Published public var volumeSize: UInt64? = nil
    /// Leave `.DS_Store` files out. Not per format: it is about the files, not
    /// the archive.
    @Published public var excludeDSStore: Bool { didSet { autosave() } }

    private let defaults: UserDefaults
    private let storage: Storage
    private var remembered: [Format: Remembered] = [:]
    /// Set while a format's settings are taken over, which changes one property
    /// after the other: storing each step would store half of one format.
    private var applying = false

    public init(defaults: UserDefaults = .standard, storage: Storage = .savePanel) {
        self.defaults = defaults
        self.storage = storage
        let decoder = JSONDecoder()
        let legacyLevel = storage.legacyLevelKey.flatMap { defaults.object(forKey: $0) as? Int }
        for format in Format.allCases {
            if let data = defaults.data(forKey: storage.settingsKey(format)),
               let stored = try? decoder.decode(Remembered.self, from: data) {
                remembered[format] = stored
            } else if let legacyLevel {
                remembered[format] = Remembered(level: UInt32(clamping: legacyLevel))
            }
        }
        let format = defaults.string(forKey: storage.formatKey).flatMap(Format.init(rawValue:)) ?? .zip
        self.format = format
        self.excludeDSStore = defaults.bool(forKey: storage.excludeDSStoreKey)
        apply(remembered[format] ?? Remembered())
    }

    // MARK: What the current format and method offer

    public var levels: [UInt32] { SevenZipCompressionOptions.levels }
    public var methods: [Method] { SevenZipCompressionOptions.methods(for: format) }
    public var dictionarySizes: [UInt64] { SevenZipCompressionOptions.dictionarySizes(for: format, method: method) }
    public var wordSizes: [UInt32] { SevenZipCompressionOptions.wordSizes(for: format, method: method) }
    public var encryptions: [Encryption] { SevenZipCompressionOptions.encryptions(for: format) }
    public var canEncryptFileNames: Bool { SevenZipCompressionOptions.canEncryptFileNames(format) }
    public var hasSolidBlocks: Bool { SevenZipCompressionOptions.hasSolidBlocks(format) }
    public var solidBlockSizes: [UInt64] { SevenZipCompressionOptions.solidBlockSizes }
    public var volumeSizes: [UInt64] { SevenZipCompressionOptions.volumeSizes }

    /// At Store nothing is compressed, so method, dictionary, word size and solid
    /// blocks do nothing.
    public var compresses: Bool { level != 0 }

    // MARK: Checks

    public var passwordProblem: PasswordProblem? {
        if password.isEmpty && passwordConfirmation.isEmpty { return nil }
        if password != passwordConfirmation { return .mismatch }
        guard format == .zip,
              !SevenZipCompressionOptions.isValidZipPassword(password, encryption: encryption) else { return nil }
        let ascii = password.unicodeScalars.allSatisfy { (0x20...0x7F).contains($0.value) }
        return ascii ? .tooLong : .notASCII
    }

    public var canSave: Bool { passwordProblem == nil }

    /// What the writer is given. Settings the format or level has no use for are
    /// left out rather than passed along to be refused.
    public var compressionOptions: SevenZipCompressionOptions {
        SevenZipCompressionOptions(
            format: format,
            level: level,
            method: compresses ? method : nil,
            solidMode: compresses && hasSolidBlocks && solidBlockSize == 0 ? false : nil,
            password: password.isEmpty ? nil : password,
            encryption: format == .zip ? encryption : nil,
            encryptFileNames: canEncryptFileNames && encryptFileNames,
            dictionarySize: compresses ? dictionarySize : nil,
            wordSize: compresses ? wordSize : nil,
            solidBlockSize: compresses && hasSolidBlocks && (solidBlockSize ?? 0) > 0 ? solidBlockSize : nil,
            volumeSize: volumeSize)
    }

    // MARK: Memory

    /// Stores the settings for the next save — every format's, the format
    /// itself, and the `.DS_Store` choice. Called when a save goes ahead.
    public func remember() {
        remembered[format] = snapshot()
        let encoder = JSONEncoder()
        for (format, settings) in remembered {
            if let data = try? encoder.encode(settings) {
                defaults.set(data, forKey: storage.settingsKey(format))
            }
        }
        defaults.set(format.rawValue, forKey: storage.formatKey)
        defaults.set(excludeDSStore, forKey: storage.excludeDSStoreKey)
    }

    private func autosave() {
        guard storage == .quickCompress, !applying else { return }
        remember()
    }

    /// The settings 7-Zip keeps per format. Methods and ciphers are stored by
    /// name, so one that stops being offered reads back as "not set" instead of
    /// failing the whole record.
    struct Remembered: Codable, Equatable {
        var level: UInt32 = 5
        var method: String?
        var dictionarySize: UInt64?
        var wordSize: UInt32?
        var solidBlockSize: UInt64?
        var encryption: String?
        var encryptFileNames = false
    }

    private func snapshot() -> Remembered {
        Remembered(level: level, method: method?.rawValue, dictionarySize: dictionarySize,
                   wordSize: wordSize, solidBlockSize: solidBlockSize,
                   encryption: encryption.rawValue, encryptFileNames: encryptFileNames)
    }

    /// Takes over `settings`, dropping whatever the current format does not offer.
    private func apply(_ settings: Remembered) {
        applying = true
        defer { applying = false }
        level = levels.contains(settings.level) ? settings.level : 5
        method = settings.method.flatMap(Method.init(rawValue:)).flatMap { methods.contains($0) ? $0 : nil }
        dictionarySize = settings.dictionarySize.flatMap { dictionarySizes.contains($0) ? $0 : nil }
        wordSize = settings.wordSize.flatMap { wordSizes.contains($0) ? $0 : nil }
        solidBlockSize = hasSolidBlocks
            ? settings.solidBlockSize.flatMap { $0 == 0 || solidBlockSizes.contains($0) ? $0 : nil }
            : nil
        encryption = settings.encryption.flatMap(Encryption.init(rawValue:)) ?? .aes256
        encryptFileNames = canEncryptFileNames && settings.encryptFileNames
    }

    /// A change of method can leave a dictionary or word size the new one does
    /// not offer.
    private func dropWhatTheMethodLacks() {
        if let size = dictionarySize, !dictionarySizes.contains(size) { dictionarySize = nil }
        if let size = wordSize, !wordSizes.contains(size) { wordSize = nil }
    }
}
