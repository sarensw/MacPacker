//
//  Changelog.swift
//  Modules
//
//  The changelog block of Config/products/macpacker.json, which the app
//  bundles and CI also renders into the release notes.
//

import Foundation

public struct Changelog: Decodable, Sendable {
    public let comingNext: [String: String]
    public let versions: [ChangelogVersion]

    /// The versions a build of `appVersion` has shipped, newest first. A dev,
    /// beta or snapshot build also lists the block that is still being written.
    public func versions(upTo appVersion: String) -> [ChangelogVersion] {
        let isDevVersion = ["dev", "snapshot", "beta"].contains { appVersion.contains($0) }
        return versions
            .filter { isDevVersion || $0.version.compare(appVersion, options: .numeric) != .orderedDescending }
            .sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }
}

public struct ChangelogVersion: Decodable, Sendable {
    public let version: String
    public let items: [ChangelogItem]

    /// What the welcome window lists: the items flagged `highlight`, or the
    /// first six when a version flags none.
    public var highlights: [ChangelogItem] {
        let flagged = items.filter { $0.highlight == true }
        return flagged.isEmpty ? Array(items.prefix(6)) : flagged
    }
}

public struct ChangelogItem: Decodable, Identifiable, Sendable {
    public var id: String { "\(type)-\(title.values.joined())" }

    public let type: String
    public let title: [String: String]
    public let issues: [String]?
    public let highlight: Bool?
}
