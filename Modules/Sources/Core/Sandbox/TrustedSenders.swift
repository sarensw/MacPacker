//
//  TrustedSenders.swift
//  Modules
//
//  Which urls a trusted app sent. MacPacker's url scheme is registered with
//  Launch Services, so any app, and any web page the user lets through, can
//  open one of its urls and ask for a Finder action, which then reads and
//  writes under the folder grants the user gave MacPacker (#286). macOS notes
//  in the url's Apple event which process asked to open it, and only what
//  MacPacker's own Finder extension sent is carried out.
//

import Foundation
import Security

@MainActor
public final class TrustedSenders {
    private let requirements: [SecRequirement]
    /// What trusted senders sent and nobody has asked about yet. A list, not a
    /// set: the same menu entry clicked twice sends the same url twice.
    private var sent: [String] = []

    /// - Parameter requirements: what a sender's code has to meet; any one of them will do
    public init(trusting requirements: [SecRequirement]) {
        self.requirements = requirements
    }

    /// Notes that `url` arrived from the process behind `auditToken`, and
    /// checks that process right away: a sender can be checked only while it
    /// is running.
    /// - Returns: whether the sender is trusted
    @discardableResult
    public func note(_ url: String, sentBy auditToken: Data?) -> Bool {
        guard let auditToken,
              requirements.contains(where: { CodeSignature.process(auditToken, satisfies: $0) }) else {
            return false
        }
        sent.append(url)
        return true
    }

    /// Whether a trusted sender sent `url`. Each note answers once.
    public func sentByTrustedSender(_ url: URL) -> Bool {
        guard let index = sent.firstIndex(of: url.absoluteString) else { return false }
        sent.remove(at: index)
        return true
    }

    /// Whether a trusted sender sent the first of `urls`, the one the app
    /// carries out when urls arrive together. The others use up their notes
    /// all the same: one left over would let the same url from another app
    /// through later.
    public func sentByTrustedSender(firstOf urls: [URL]) -> Bool {
        urls.map { sentByTrustedSender($0) }.first ?? false
    }
}

/// The code signatures of running processes and of code on disk.
public enum CodeSignature {
    /// The designated requirement of the code at `url`: what this code and any
    /// later version of it meet, and nothing else does. For an ad-hoc signature
    /// that is the code's hash, so only this very build.
    public static func designatedRequirement(ofCodeAt url: URL) -> SecRequirement? {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess else {
            return nil
        }
        return requirement
    }

    /// Whether the process behind `auditToken` runs code that meets
    /// `requirement`. Not once it has quit: the token names that process
    /// alone, and a new process that got its pid has another pid version.
    public static func process(_ auditToken: Data, satisfies requirement: SecRequirement) -> Bool {
        guard let code = code(of: auditToken) else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    /// The signing identifier of the process behind `auditToken`, for the log.
    public static func identifier(ofProcess auditToken: Data) -> String? {
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard let code = code(of: auditToken),
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, [], &info) == errSecSuccess else {
            return nil
        }
        return (info as? [String: Any])?[kSecCodeInfoIdentifier as String] as? String
    }

    private static func code(of auditToken: Data) -> SecCode? {
        var code: SecCode?
        let attributes = [kSecGuestAttributeAudit: auditToken] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess else { return nil }
        return code
    }
}
