//
//  AppUrl.swift
//  Modules
//
//  Created by Stephan Arenswald on 10.09.26.
//

import Foundation

/// What the Finder extension asks the main app to do.
public enum AppUrlAction: String, Sendable {
    case open
    case extractHere
    case extractToFolder
    case extractTo
    case compress
    case compressEach
    case compressContents
    case addToArchive
}

/// A request from the Finder extension, sent as
/// `<scheme>://<action>?files=…&target=…[&format=…][&dated=<seconds since 1970>]`.
///
/// The scheme is registered with Launch Services, so any app or web page can
/// open such a url: all of it is untrusted input, and parsing is where it gets
/// checked.
public struct AppUrl: Equatable, Sendable {
    public var action: AppUrlAction
    public var files: [URL]
    public var target: URL
    /// Extension of the archive to produce, for `compress`; `nil` means zip.
    /// Always one the menu itself produces — it ends up in a file name.
    public var format: String?
    /// When the menu showed the dated entry, for `compress`; `nil` for an
    /// undated archive. The name is built from this moment, not from when the
    /// archive gets written, so it matches what the menu displayed.
    public var datedAt: Date?

    public enum ParseError: Error, Equatable {
        case wrongScheme(String?)
        case unknownAction(String?)
        case missingFilesOrTarget
        case unsupportedFormat(String)
        case invalidDate(String)
    }

    /// Parses a url in the Finder extension's format; throws for anything else.
    public init(url: URL, scheme: String) throws(ParseError) {
        guard url.scheme == scheme else {
            throw .wrongScheme(url.scheme)
        }
        guard let action = url.host().flatMap(AppUrlAction.init(rawValue:)) else {
            throw .unknownAction(url.host())
        }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        // the extension percent-encodes the paths once more before the query
        // encodes them, hence the extra decode. A path that doesn't decode to
        // an absolute path would resolve against the app's working directory,
        // so it rejects the whole request.
        func decodedPath(_ encoded: String) -> String? {
            guard let path = encoded.removingPercentEncoding, path.hasPrefix("/") else { return nil }
            return path
        }
        let filePaths = (value("files") ?? "").split(separator: ",").map { decodedPath(String($0)) }
        guard let targetPath = value("target").flatMap(decodedPath),
              !filePaths.isEmpty, !filePaths.contains(nil) else {
            throw .missingFilesOrTarget
        }
        let format = value("format")
        if let format, !FinderMenuItem.isArchiveExtension(format) {
            throw .unsupportedFormat(format)
        }

        self.action = action
        self.files = filePaths.compactMap { $0 }.map { URL(fileURLWithPath: $0) }
        self.target = URL(fileURLWithPath: targetPath)
        self.format = format
        if let dated = value("dated") {
            // digits only, so nothing but a date can reach the file name
            guard let seconds = Int(dated) else {
                throw .invalidDate(dated)
            }
            self.datedAt = Date(timeIntervalSince1970: TimeInterval(seconds))
        } else {
            self.datedAt = nil
        }
    }

    /// The archive's file name for this request: `base` as the compress rule
    /// builds it, plus the menu's moment when the dated entry sent it.
    public func archiveName(_ base: String, extension ext: String) -> String {
        guard let datedAt else { return base }
        return FinderMenuItem.datedName(base, extension: ext, at: datedAt)
    }
}
