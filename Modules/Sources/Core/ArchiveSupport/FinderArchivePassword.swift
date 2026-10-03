import Foundation
import Security
import Swift7zip

/// Passwords used by Finder's one-step encrypted archive actions. They are
/// never stored in preferences or passed through the app's URL scheme.
public enum FinderArchivePassword {
    /// 24 characters from a 64-character alphabet: 144 bits of randomness.
    public static func generate() throws -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8)
        var bytes = [UInt8](repeating: 0, count: 24)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return String(decoding: bytes.map { alphabet[Int($0 & 63)] }, as: UTF8.self)
    }

    /// 7z uses AES-256 and can hide file names as well as file contents.
    public static func compressionOptions(password: String) -> CompressionOptions {
        CompressionOptions(format: .sevenZ, password: password, encryptFileNames: true)
    }
}
