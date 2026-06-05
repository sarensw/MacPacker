//
//  Cache.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 22.11.23.
//

import Core
import Foundation
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "cache")

class CacheCleaner {
    private let applicationSupportDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    
    func clean() {
        if let url = applicationSupportDirectory {
            do {
                try FileManager.default.removeItem(at: url.appendingPathComponent("ta", conformingTo: .directory))
            } catch {
                log.error("Could not clear cache", context: ["error": error.localizedDescription])
            }
        }
    }
    
    func clean(tempDirectories: [URL]) {
        for url in tempDirectories {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                log.error("Could not clear cache", context: ["error": error.localizedDescription])
            }
        }
    }
}
