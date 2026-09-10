//
//  AppUrlTests.swift
//  Modules
//
//  `AppUrl` parses what arrives through MacPacker's url scheme. Any app or web
//  page can open such a url, and its `format` ends up in the name of the
//  archive the app writes — so a format that could climb out of the target
//  folder must reject the whole url before any handler sees it.
//

import Foundation
import Testing
@testable import FinderMenu

extension AllCoreTests {
    struct AppUrlTests {

        private let scheme = "app.macpacker"

        /// Builds a url the way the Finder extension does: the paths are
        /// percent-encoded once, then the query encodes them again.
        private func url(
            _ action: String,
            files: [String] = ["/Users/me/Photos"],
            target: String? = "/Users/me",
            extra: [URLQueryItem] = [],
            scheme: String? = nil
        ) -> URL {
            var components = URLComponents(string: "\(scheme ?? self.scheme)://\(action)")!
            var items: [URLQueryItem] = []
            if !files.isEmpty {
                let joined = files.joined(separator: ",").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                items.append(URLQueryItem(name: "files", value: joined))
            }
            if let target {
                items.append(URLQueryItem(name: "target", value: target.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)))
            }
            components.queryItems = items + extra
            return components.url!
        }

        @Test("A compress url from the Finder extension parses completely")
        func parsesFinderUrl() throws {
            let parsed = try AppUrl(url: url("compress", files: ["/Users/me/My Photos", "/Users/me/notes.txt"], extra: [
                URLQueryItem(name: "format", value: "7z"),
                URLQueryItem(name: "dated", value: "1"),
            ]), scheme: scheme)

            #expect(parsed.action == .compress)
            #expect(parsed.files == [URL(fileURLWithPath: "/Users/me/My Photos"), URL(fileURLWithPath: "/Users/me/notes.txt")])
            #expect(parsed.target == URL(fileURLWithPath: "/Users/me"))
            #expect(parsed.format == "7z")
            #expect(parsed.dated)
        }

        @Test("A format that is not the menu's own rejects the whole url",
              arguments: ["zip/../../evil", "../zip", "..", "7z/x", "/tmp/x", "rar", ""])
        func unsafeFormatIsRejected(format: String) {
            #expect(throws: AppUrl.ParseError.unsupportedFormat(format)) {
                try AppUrl(url: url("compress", extra: [URLQueryItem(name: "format", value: format)]), scheme: scheme)
            }
        }

        @Test("Without a format the app falls back to zip")
        func missingFormatIsNil() throws {
            #expect(try AppUrl(url: url("compress"), scheme: scheme).format == nil)
        }

        @Test("Another scheme, an unknown action or a missing file or target is rejected")
        func malformedUrlsAreRejected() {
            #expect(throws: AppUrl.ParseError.wrongScheme("https")) {
                try AppUrl(url: url("compress", scheme: "https"), scheme: scheme)
            }
            #expect(throws: AppUrl.ParseError.unknownAction("deleteEverything")) {
                try AppUrl(url: url("deleteEverything"), scheme: scheme)
            }
            #expect(throws: AppUrl.ParseError.missingFilesOrTarget) {
                try AppUrl(url: url("compress", target: nil), scheme: scheme)
            }
            #expect(throws: AppUrl.ParseError.missingFilesOrTarget) {
                try AppUrl(url: url("compress", files: []), scheme: scheme)
            }
        }
    }
}
