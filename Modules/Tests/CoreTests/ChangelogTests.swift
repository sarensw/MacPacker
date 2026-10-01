//
//  ChangelogTests.swift
//  Modules
//
//  What the welcome window takes from the bundled changelog: the highlights of
//  the running version, and every version it has shipped for "View all changes".
//

import Testing
import Foundation
@testable import Core

extension AllCoreTests {

    struct ChangelogTests {

        private func changelog(_ json: String) throws -> Changelog {
            try JSONDecoder().decode(Changelog.self, from: Data(json.utf8))
        }

        private func item(_ title: String, highlight: Bool = false) -> String {
            #"{"type": "feat", "title": {"en": "\#(title)"}, "issues": []\#(highlight ? #", "highlight": true"# : "")}"#
        }

        private func versions(_ numbers: String...) throws -> Changelog {
            let blocks = numbers.map { #"{"version": "\#($0)", "items": [\#(item($0))]}"# }
            return try changelog(#"{"comingNext": {}, "versions": [\#(blocks.joined(separator: ","))]}"#)
        }

        /// 0.9.0 sorts below 0.22.0: versions compare by number, not as text.
        @Test func aReleaseListsTheVersionsItShippedNewestFirst() throws {
            let log = try versions("1.0.0", "0.9.0", "0.22.0")
            #expect(log.versions(upTo: "0.22.0").map(\.version) == ["0.22.0", "0.9.0"])
        }

        @Test(arguments: ["0.0.0-dev", "1.0.0-beta.2"])
        func aDevOrBetaBuildAlsoListsTheBlockInProgress(appVersion: String) throws {
            let log = try versions("0.22.0", "1.0.0")
            #expect(log.versions(upTo: appVersion).map(\.version) == ["1.0.0", "0.22.0"])
        }

        @Test func highlightsAreTheFlaggedItems() throws {
            let items = [item("a"), item("b", highlight: true), item("c"), item("d", highlight: true)]
            let log = try changelog(#"{"comingNext": {}, "versions": [{"version": "1.0.0", "items": [\#(items.joined(separator: ","))]}]}"#)
            #expect(log.versions[0].highlights.map { $0.title["en"] } == ["b", "d"])
        }

        @Test func aVersionWithoutFlagsHighlightsItsFirstSixItems() throws {
            let items = (1...8).map { item("\($0)") }
            let log = try changelog(#"{"comingNext": {}, "versions": [{"version": "1.0.0", "items": [\#(items.joined(separator: ","))]}]}"#)
            #expect(log.versions[0].highlights.map { $0.title["en"] } == ["1", "2", "3", "4", "5", "6"])
        }

        /// The file the app bundles still decodes, and its newest block names
        /// the highlights the welcome window shows.
        @Test func theBundledChangelogDecodes() throws {
            let file = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: "Config/products/macpacker.json")
            struct ProductFile: Decodable { let changelog: Changelog }
            let log = try JSONDecoder().decode(ProductFile.self, from: Data(contentsOf: file)).changelog
            let newest = try #require(log.versions(upTo: "0.0.0-dev").first)
            #expect(newest.items.contains { $0.highlight == true })
        }
    }
}
