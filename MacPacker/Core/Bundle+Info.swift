//
//  Bundle+Info.swift
//  MacPacker
//
//  Convenience accessors for Info.plist values. These were previously provided
//  by TailBeatKit's Bundle extension; reimplemented locally after moving logging
//  to OSLog (the `tb` module no longer ships these).
//

import Foundation

extension Bundle {
    var appName: String { getInfo("CFBundleName") }
    var displayName: String { getInfo("CFBundleDisplayName") }
    var language: String { getInfo("CFBundleDevelopmentRegion") }
    var identifier: String { getInfo("CFBundleIdentifier") }
    var copyright: String { getInfo("NSHumanReadableCopyright").replacingOccurrences(of: "\\n", with: "\n") }

    var appBuild: String { getInfo("CFBundleVersion") }
    var appVersionLong: String { getInfo("CFBundleShortVersionString") }

    private func getInfo(_ key: String) -> String { infoDictionary?[key] as? String ?? "⚠️" }
}
