//
//  ArchiveError.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 06.09.25.
//


import Foundation

enum ArchiveError: Error, LocalizedError {
    // used to say that the archive is invalid and cannot be extracted
    case invalidArchive(_ message: String)
    case loadFailed(_ message: String)
    case extractionFailed(_ message: String)
    case passwordCancelled
    case xadError(_ code: Int32, _ message: String)

    /// Without this the UI shows `localizedDescription`'s generic "The operation
    /// couldn't be completed" for every one of these, which is how a wrong
    /// password ended up with no message at all.
    var errorDescription: String? {
        switch self {
        case .invalidArchive(let message): return message
        case .loadFailed(let message): return message
        case .extractionFailed(let message): return message
        case .passwordCancelled: return "Password entry was cancelled."
        case .xadError(let code, let message): return "\(message) (error \(code))"
        }
    }
}
