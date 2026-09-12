import Foundation

/// Options controlling archive creation and update.
public struct SevenZipCompressionOptions: Sendable {

    /// Supported output archive formats.
    public enum Format: String, Sendable, CaseIterable {
        /// 7z format (LZMA2 by default).
        case sevenZ = "7z"
        /// Zip format (Deflate by default).
        case zip = "zip"
    }

    /// Compression method.
    public enum Method: String, Sendable, CaseIterable {
        /// LZMA2 (default for 7z).
        case lzma2 = "lzma2"
        /// LZMA.
        case lzma = "lzma"
        /// Deflate (default for zip).
        case deflate = "deflate"
        /// BZip2.
        case bzip2 = "bzip2"
        /// PPMd.
        case ppmd = "ppmd"
        /// Store only (no compression).
        case copy = "copy"
    }

    /// How a zip archive is encrypted. 7z always uses AES-256.
    public enum Encryption: String, Sendable, CaseIterable {
        /// WinZip's AES with a 256-bit key: what current tools read.
        case aes256 = "AES256"
        /// PKWARE's original scheme. Easily broken, but the only one some old
        /// tools, Windows' built-in extractor among them, can open.
        case zipCrypto = "ZipCrypto"
    }

    /// Archive format. Default: `.sevenZ`.
    public var format: Format

    /// 7-Zip's levels, Store through Ultra.
    public static let levels: [UInt32] = [0, 1, 3, 5, 7, 9]

    /// What `method` stands for in `format`: the format's default for `nil`.
    public static func effectiveMethod(_ method: Method?, in format: Format) -> Method {
        method ?? (format == .zip ? .deflate : .lzma2)
    }

    /// Dictionary sizes worth offering, in bytes: the model's memory for PPMd,
    /// the block size for BZip2. Empty where the method has nothing to choose.
    /// Capped at 256 MB, since compressing takes roughly eleven times the
    /// dictionary in memory.
    public static func dictionarySizes(for format: Format, method: Method?) -> [UInt64] {
        let mb: UInt64 = 1 << 20
        switch effectiveMethod(method, in: format) {
        case .lzma, .lzma2: return [64 << 10, 1 * mb, 4 * mb, 16 * mb, 32 * mb, 64 * mb, 128 * mb, 256 * mb]
        case .ppmd: return [4 * mb, 16 * mb, 64 * mb, 256 * mb]
        case .bzip2: return [100_000, 300_000, 500_000, 900_000]
        case .deflate, .copy: return []
        }
    }

    /// Word sizes worth offering: fast bytes for LZMA and Deflate, the model
    /// order for PPMd. Empty where the method has nothing to choose.
    public static func wordSizes(for format: Format, method: Method?) -> [UInt32] {
        switch effectiveMethod(method, in: format) {
        case .lzma, .lzma2: return [16, 32, 64, 128, 273]
        case .deflate: return [32, 64, 128, 258]
        case .ppmd: return format == .zip ? [4, 6, 8, 16] : [4, 6, 8, 16, 32]
        case .bzip2, .copy: return []
        }
    }

    /// Ways `format` can be encrypted, best first. Empty for 7z, which has only
    /// AES-256 and so nothing to choose.
    public static func encryptions(for format: Format) -> [Encryption] {
        format == .zip ? [.aes256, .zipCrypto] : []
    }

    /// Longest password WinZip's AES takes, per 7-Zip.
    public static let zipAESPasswordLimit = 99

    /// Whether 7-Zip can encrypt a zip with `password`. Zip keeps passwords as
    /// plain ASCII — 7-Zip refuses anything else, for AES and ZipCrypto alike —
    /// and AES has a length limit on top. 7z takes any password.
    public static func isValidZipPassword(_ password: String, encryption: Encryption?) -> Bool {
        let ascii = password.unicodeScalars.allSatisfy { (0x20...0x7F).contains($0.value) }
        return ascii && (encryption == .zipCrypto || password.count <= zipAESPasswordLimit)
    }

    /// Whether `format` can hide its file names behind the password: 7z can,
    /// a zip lists them in the clear.
    public static func canEncryptFileNames(_ format: Format) -> Bool { format == .sevenZ }

    /// Whether `format` has solid blocks: 7z does, zip packs each file alone.
    public static func hasSolidBlocks(_ format: Format) -> Bool { format == .sevenZ }

    /// Solid block sizes worth offering, in bytes; `.max` is one block for all.
    public static let solidBlockSizes: [UInt64] = [1 << 20, 16 << 20, 256 << 20, 2 << 30, .max]

    /// Volume sizes worth offering, in bytes — 7-Zip's megabytes (2^20), with
    /// FAT32's largest file as the top one.
    public static let volumeSizes: [UInt64] = [10, 25, 100, 700, 1000, 4092].map { $0 << 20 }

    /// Methods 7-Zip's writer accepts for this container, best first. Picking
    /// one outside this list makes the write fail, so the UI offers only these.
    public static func methods(for format: Format) -> [Method] {
        switch format {
        case .zip:    return [.deflate, .bzip2, .lzma, .ppmd]
        case .sevenZ: return [.lzma2, .lzma, .ppmd, .bzip2, .copy]
        }
    }

    /// Compression level from 0 (store) through 9 (ultra). Default: 5.
    /// At 0 nothing is compressed, whatever `method` says.
    public var level: UInt32

    /// Compression method. `nil` uses the format default
    /// (LZMA2 for 7z, Deflate for zip).
    public var method: Method?

    /// Solid archive mode. `nil` uses the format default (on for 7z).
    public var solidMode: Bool?

    /// Password to encrypt with. `nil` or empty writes an unencrypted archive.
    public var password: String?

    /// Zip only; `nil` is AES-256.
    public var encryption: Encryption?

    /// 7z only: encrypt the file list too, so opening the archive at all takes
    /// the password.
    public var encryptFileNames: Bool

    /// Dictionary size in bytes — the model's memory for PPMd, the block size
    /// for BZip2. `nil` leaves it to the level.
    public var dictionarySize: UInt64?

    /// Word size: fast bytes for LZMA and Deflate, the model order for PPMd.
    /// `nil` leaves it to the level.
    public var wordSize: UInt32?

    /// 7z only: bytes per solid block, `.max` for one block. `nil` leaves it to
    /// the level; `solidMode: false` turns solid blocks off.
    public var solidBlockSize: UInt64?

    /// Split the archive into volumes of this many bytes, written as
    /// `name.001`, `name.002`, ... next to the destination. `nil` writes one file.
    public var volumeSize: UInt64?

    /// Whether this writes an encrypted archive.
    public var encrypts: Bool { !(password ?? "").isEmpty }

    /// Creates compression options with sensible defaults.
    public init(
        format: Format = .sevenZ,
        level: UInt32 = 5,
        method: Method? = nil,
        solidMode: Bool? = nil,
        password: String? = nil,
        encryption: Encryption? = nil,
        encryptFileNames: Bool = false,
        dictionarySize: UInt64? = nil,
        wordSize: UInt32? = nil,
        solidBlockSize: UInt64? = nil,
        volumeSize: UInt64? = nil
    ) {
        self.format = format
        self.level = level
        self.method = method
        self.solidMode = solidMode
        self.password = password
        self.encryption = encryption
        self.encryptFileNames = encryptFileNames
        self.dictionarySize = dictionarySize
        self.wordSize = wordSize
        self.solidBlockSize = solidBlockSize
        self.volumeSize = volumeSize
    }
}
