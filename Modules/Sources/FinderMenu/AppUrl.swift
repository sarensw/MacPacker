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

public extension AppUrlAction {
    /// Whether the smart-extraction setting gets a say in where this action's
    /// output lands.
    ///
    /// `extractToFolder` is named after the folder it creates, and creates it
    /// itself — the question is already answered, and letting the rule wrap a
    /// second container inside would give exactly the `Photos/Photos` nesting
    /// smart extraction exists to prevent. Every other extracting action hands
    /// the user's own destination to the extractor, and there the setting
    /// decides.
    var honorsSmartExtraction: Bool {
        switch self {
        case .extractHere, .extractTo:
            true
        case .extractToFolder, .open, .compress, .compressEach,
             .compressContents, .addToArchive:
            false
        }
    }
}

public extension AppUrlAction {
    /// Whether the app comes to the front for this action: it opens a window
    /// to work in, or starts by asking where to. Every other action extracts
    /// or compresses while the user stays in Finder, which keeps the focus
    /// from the click to the result (#279).
    var bringsAppToFront: Bool {
        switch self {
        case .open, .addToArchive, .extractTo:
            true
        case .extractHere, .extractToFolder, .compress, .compressEach,
             .compressContents:
            false
        }
    }
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

    public init(action: AppUrlAction, files: [URL], target: URL, format: String? = nil, datedAt: Date? = nil) {
        self.action = action
        self.files = files
        self.target = target
        self.format = format
        self.datedAt = datedAt
    }

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

    /// The url the Finder extension sends for this request — the other half of
    /// `init(url:scheme:)`. Each path is percent-encoded on its own, commas
    /// included, before the paths are joined with commas, so a comma in a file
    /// name can't split it.
    public func url(scheme: String) -> URL? {
        let pathAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: ","))
        func encode(_ url: URL) -> String? {
            url.path.addingPercentEncoding(withAllowedCharacters: pathAllowed)
        }
        let paths = files.map(encode)
        guard let encodedTarget = encode(target), !paths.contains(nil) else { return nil }

        var items = [
            URLQueryItem(name: "files", value: paths.compactMap { $0 }.joined(separator: ",")),
            URLQueryItem(name: "target", value: encodedTarget),
        ]
        if let format {
            items.append(URLQueryItem(name: "format", value: format))
        }
        if let datedAt {
            items.append(URLQueryItem(name: "dated", value: String(Int(datedAt.timeIntervalSince1970))))
        }
        var components = URLComponents(string: "\(scheme)://\(action.rawValue)")
        components?.queryItems = items
        return components?.url
    }
}

public extension AppUrl {
    /// The folder an action puts what it makes of `item` in — what comes out
    /// of an archive, or one item's own archive: the item's own. `target` is
    /// the folder Finder's window shows, which is not always the item's: an
    /// item in a folder expanded in list view sits in a subfolder of it.
    func folder(of item: URL) -> URL {
        item.deletingLastPathComponent()
    }

    /// The folder an action that makes one archive of all `files` puts it in:
    /// the deepest folder holding every one of them — their own when they
    /// share it, the window's when some sit in a folder expanded in it.
    var folderOfFiles: URL {
        Self.folder(containing: files) ?? target
    }

    /// The deepest folder holding every one of `items`; `nil` for none. The
    /// Finder extension names the archive in its menu after it, before there
    /// is a url.
    static func folder(containing items: [URL]) -> URL? {
        let parents = items.map { $0.deletingLastPathComponent().standardizedFileURL.pathComponents }
        guard var common = parents.first else { return nil }
        for components in parents.dropFirst() {
            common = zip(common, components).prefix { $0 == $1 }.map(\.0)
        }
        return URL(fileURLWithPath: NSString.path(withComponents: common), isDirectory: true)
    }

    /// Of what an action put in place, what to select in Finder afterwards:
    /// what is in the window's own folder (`target`). Finder selects in an
    /// open window only what lies in that window's own folder, and opens a
    /// second window for anything else — for a result in an expanded
    /// subfolder, too, which the window already shows as it is.
    func itemsToSelect(_ placed: [URL]) -> [URL] {
        let window = target.standardizedFileURL.path
        return placed.filter { $0.deletingLastPathComponent().standardizedFileURL.path == window }
    }
}
