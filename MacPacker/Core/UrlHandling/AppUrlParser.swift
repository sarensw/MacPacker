//
//  UrlHandler.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 24.09.25.
//

import Core
import Foundation
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "url")

enum AppUrlAction: String {
    case open
    case extractHere
    case extractToFolder
    case extractTo
    case compress
    case compressEach
    case compressContents
    case addToArchive
}

struct AppUrl {
    var action: AppUrlAction
    var files: [URL]
    var target: URL
    /// Extension of the archive to produce, for `compress`. `nil` means zip.
    var format: String?
    /// Whether the archive's name carries the date and time, for `compress`.
    var dated: Bool = false
}

class UrlParser {
    
    /// The app's custom URL scheme, read from Info.plist so Debug and Release builds
    /// (which register different schemes) stay in sync with the build automatically.
    static let appScheme: String = Bundle.main.object(forInfoDictionaryKey: "MacPackerURLScheme") as? String ?? ""

    func parse(appUrl: URL) -> AppUrl? {
        // we're just reacting on the app's registered scheme here
        if appUrl.scheme != UrlParser.appScheme {
            log.warning("wrong scheme \(String(describing: appUrl.scheme)) found")
            return nil
        }
        
        // check the action
        guard let actionString = appUrl.host() else {
            log.warning("correct scheme, but action could not be extracted")
            return nil
        }
        guard let action = AppUrlAction(rawValue: actionString) else {
            log.warning("unknown action \(actionString)")
            return nil
        }
        
        var files: [URL] = []
        var target: URL? = nil
        var format: String? = nil
        var dated = false

        if let comps = URLComponents(
            url: appUrl,
            resolvingAgainstBaseURL: false),
           let queryItems = comps.queryItems
        {
            if let queryFilesString = queryItems.first(where: { $0.name == "files" })?.value {
                let queryFiles = queryFilesString.split(separator: ",")
                for queryFile in queryFiles {
                    let filePath = String(queryFile).removingPercentEncoding ?? ""
                    let fileUrl = URL(fileURLWithPath: filePath)
                    files.append(fileUrl)
                }
            }
            
            if let queryTargetString = queryItems.first(where: { $0.name == "target" })?.value {
                let queryTarget = queryTargetString.removingPercentEncoding ?? ""
                target = URL(fileURLWithPath: queryTarget)
            }

            format = queryItems.first(where: { $0.name == "format" })?.value
            dated = queryItems.first(where: { $0.name == "dated" })?.value == "1"
        }
        
        guard let target,
              !files.isEmpty else
        {
            log.warning("could not parse url correctly (no files?: \(files.isEmpty)) (no target?: \(target == nil))")
            return nil
        }
        
        let appUrl = AppUrl(
            action: action,
            files: files,
            target: target,
            format: format,
            dated: dated
        )
        log.notice("Parsed app url: action=\(action.rawValue), files=\(files.count), target=\(target.lastPathComponent), format=\(format ?? "-"), dated=\(dated)")
        return appUrl
    }
    
}
