//
//  Cache.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 22.11.23.
//

import Foundation

class CacheCleaner {
    private let applicationSupportDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    
    func clean() {
        if let url = applicationSupportDirectory {
            do {
                try FileManager.default.removeItem(at: url.appendingPathComponent("ta", conformingTo: .directory))
            } catch {
                Logger.error("Could not clear cache because...")
                Logger.error(error.localizedDescription)
            }
        }
    }
    
    func clean(tempDirectories: [URL]) {
        for url in tempDirectories {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                Logger.error("Could not clear cache because...")
                Logger.error(error.localizedDescription)
            }
        }
    }
}
