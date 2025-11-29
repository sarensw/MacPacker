//
//  UrlHandler.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 24.09.25.
//

import Core
import Foundation

enum AppUrlAction: String {
    case open
    case extractFiles
    case extractHere
    case extractToFolder
}

struct AppUrl {
    var action: AppUrlAction
    var files: [URL]
    var target: URL
}

class UrlParser {
    
    func parse(appUrl: URL) -> AppUrl? {
        // we're just reacting on "app.macpacker" scheme here
        if appUrl.scheme != "app.macpacker" {
            Logger.warning("wrong scheme \(String(describing: appUrl.scheme)) found")
            return nil
        }
        
        // check the action
        guard let actionString = appUrl.host() else {
            Logger.warning("correct scheme, but action could not be extracted")
            return nil
        }
        guard let action = AppUrlAction(rawValue: actionString) else {
            Logger.warning("unknown action \(actionString)")
            return nil
        }
        
        var files: [URL] = []
        var target: URL? = nil
        
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
        }
        
        guard let target,
              !files.isEmpty else
        {
            Logger.warning("could not parse url correctly (no files?: \(files.isEmpty)) (no target?: \(target == nil))")
            return nil
        }
        
        let appUrl = AppUrl(
            action: action,
            files: files,
            target: target
        )
        return appUrl
    }
    
}
