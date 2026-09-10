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
/// `<scheme>://<action>?files=…&target=…[&format=…][&dated=1]`.
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
    /// Whether the archive's name carries the date and time, for `compress`.
    public var dated: Bool

    public enum ParseError: Error, Equatable {
        case wrongScheme(String?)
        case unknownAction(String?)
        case missingFilesOrTarget
        case unsupportedFormat(String)
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
        // encodes them, hence the extra decode
        let files = (value("files") ?? "")
            .split(separator: ",")
            .map { URL(fileURLWithPath: String($0).removingPercentEncoding ?? "") }
        guard let target = value("target"), !files.isEmpty else {
            throw .missingFilesOrTarget
        }
        let format = value("format")
        if let format, !FinderMenuItem.isArchiveExtension(format) {
            throw .unsupportedFormat(format)
        }

        self.action = action
        self.files = files
        self.target = URL(fileURLWithPath: target.removingPercentEncoding ?? "")
        self.format = format
        self.dated = value("dated") == "1"
    }
}
