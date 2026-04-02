import Foundation

/// Options controlling archive creation and update.
public struct SevenZipCompressionOptions: Sendable {

    /// Supported output archive formats.
    public enum Format: String, Sendable {
        /// 7z format (LZMA2 by default).
        case sevenZ = "7z"
        /// Zip format (Deflate by default).
        case zip = "zip"
    }

    /// Compression method.
    public enum Method: String, Sendable {
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

    /// Archive format. Default: `.sevenZ`.
    public var format: Format

    /// Compression level from 0 (store) through 9 (ultra). Default: 5.
    public var level: UInt32

    /// Compression method. `nil` uses the format default
    /// (LZMA2 for 7z, Deflate for zip).
    public var method: Method?

    /// Solid archive mode. `nil` uses the format default (on for 7z).
    public var solidMode: Bool?

    /// Creates compression options with sensible defaults.
    public init(
        format: Format = .sevenZ,
        level: UInt32 = 5,
        method: Method? = nil,
        solidMode: Bool? = nil
    ) {
        self.format = format
        self.level = level
        self.method = method
        self.solidMode = solidMode
    }
}
