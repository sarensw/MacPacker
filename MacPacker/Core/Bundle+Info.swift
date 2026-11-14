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

    // Localized where InfoPlist.strings has the key: the App Store build is
    // named MacPacker only there (#258).
    private func getInfo(_ key: String) -> String { object(forInfoDictionaryKey: key) as? String ?? "⚠️" }
}
