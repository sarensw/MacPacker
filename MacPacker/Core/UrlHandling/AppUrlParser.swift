//
//  UrlHandler.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 24.09.25.
//

import FinderMenu
import Foundation
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "url")

/// Turns an incoming url into an `AppUrl`. The parsing and its checks live in
/// `FinderMenu`, where the unit tests reach them; this adds the app's scheme
/// and the logging.
class UrlParser {
    
    /// The app's custom URL scheme, read from Info.plist so Debug and Release builds
    /// (which register different schemes) stay in sync with the build automatically.
    static let appScheme: String = Bundle.main.object(forInfoDictionaryKey: "MacPackerURLScheme") as? String ?? ""

    func parse(appUrl: URL) -> AppUrl? {
        do {
            let parsed = try AppUrl(url: appUrl, scheme: UrlParser.appScheme)
            log.notice("Parsed app url: action=\(parsed.action.rawValue), files=\(parsed.files.count), target=\(parsed.target.lastPathComponent), format=\(parsed.format ?? "-"), datedAt=\(parsed.datedAt.map { "\($0)" } ?? "-")")
            return parsed
        } catch {
            log.warning("Not an app url: \(error)")
            return nil
        }
    }
}
