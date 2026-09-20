//
//  ArchivePasswordAttempts.swift
//  Modules
//
//  Created by Stephan Arenswald on 20.09.26.
//

import Foundation

/// The passwords to try for one archive, in order, carrying the attempt number
/// the resolver needs to tell a first guess from a correction.
///
/// One per archive being opened. Both engines used to keep their own copy of
/// this loop and its ceiling; what they disagree about is which failure looks
/// like a wrong password, never how many times to ask.
final class ArchivePasswordAttempts {
    private let url: URL
    private let resolver: ArchivePasswordResolver
    private var attempt = 0

    /// How many passwords one archive is asked for before giving up. A resolver
    /// that keeps answering with the same wrong password — a stale cache, a
    /// scripted caller — would otherwise spin the loop forever at full CPU
    /// without ever surfacing an error.
    private static let maxAttempts = 20

    init(url: URL, resolver: @escaping ArchivePasswordResolver) {
        self.url = url
        self.resolver = resolver
    }

    /// The next password to try.
    ///
    /// - Throws: ``ArchiveError/passwordCancelled`` when the prompt is
    ///   dismissed, ``ArchiveError/extractionFailed(_:)`` once the archive has
    ///   been asked about often enough that a wrong password has stopped being
    ///   the likeliest explanation.
    func next() async throws -> String {
        guard let password = try await nextIfOffered() else {
            throw ArchiveError.passwordCancelled
        }
        return password
    }

    /// The next password, or nil when nobody answered.
    ///
    /// For the places where a password helps but its absence is not a failure:
    /// an archive whose names read fine without one still lists them. Quick Look
    /// and Finder's "Extract Here" build their state with no prompt at all, and
    /// they have to keep showing what they can.
    func nextIfOffered() async throws -> String? {
        attempt += 1
        // Neither 7z AES nor most of what XADMaster reads stores a password
        // verifier, so a failed decrypt and a damaged encrypted entry are
        // genuinely indistinguishable. Say both rather than insist on the
        // password when we cannot know.
        guard attempt <= Self.maxAttempts else {
            throw ArchiveError.extractionFailed(
                "Could not decrypt \(url.lastPathComponent) after \(Self.maxAttempts) attempts. The password may be wrong, or the archive may be damaged.")
        }
        return await resolver(ArchivePasswordRequest(url: url, attempt: attempt))
    }
}
