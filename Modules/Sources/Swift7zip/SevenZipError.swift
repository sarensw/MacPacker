import Foundation

/// Typed errors for archive operations.
/// All bridge failures are mapped to one of these cases.
public enum SevenZipError: Error, LocalizedError, Sendable {
    /// The archive could not be opened.
    case openFailed(String)
    /// An entry at the given index could not be read.
    case entryAccessFailed(UInt32)
    /// Extraction of one or more entries failed.
    case extractionFailed(String)
    /// The entry is encrypted and no password was provided.
    case passwordMissing

    /// A human-readable description of the error.
    public var errorDescription: String? {
        switch self {
        case .openFailed(let msg):
            return "Failed to open archive: \(msg)"
        case .entryAccessFailed(let idx):
            return "Failed to read entry at index \(idx)"
        case .extractionFailed(let msg):
            return "Extraction failed: \(msg)"
        case .passwordMissing:
            return "Entry is encrypted and no password was provided"
        }
    }
}
