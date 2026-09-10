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

        /// Builds a url by hand, the way any other app could send one. What the
        /// Finder extension really sends goes through `AppUrl.url(scheme:)`.
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

        @Test("A request from the Finder extension survives the trip through its url")
        func roundTrip() throws {
            let request = AppUrl(
                action: .compress,
                files: [URL(fileURLWithPath: "/Users/me/My Photos"), URL(fileURLWithPath: "/Users/me/notes.txt")],
                target: URL(fileURLWithPath: "/Users/me"),
                format: "7z",
                datedAt: Date(timeIntervalSince1970: 1_789_050_600)
            )
            let url = try #require(request.url(scheme: scheme))
            #expect(try AppUrl(url: url, scheme: scheme) == request)
        }

        @Test("The dated archive gets the name the menu showed, even after a minute boundary")
        func datedNameMatchesTheMenu() throws {
            // the menu opens a second before the minute turns; the archive is
            // written after it — every time zone's minutes turn together
            let minuteBoundary = Date(timeIntervalSince1970: 60 * 29_817_510)
            let menuShownAt = minuteBoundary.addingTimeInterval(-1)
            let writtenAt = minuteBoundary.addingTimeInterval(1)
            let displayed = FinderMenuItem.datedName("photos.zip", extension: "zip", at: menuShownAt)

            let parsed = try AppUrl(url: url("compress", extra: [
                URLQueryItem(name: "format", value: "zip"),
                URLQueryItem(name: "dated", value: String(Int(menuShownAt.timeIntervalSince1970))),
            ]), scheme: scheme)

            #expect(parsed.archiveName("photos.zip", extension: "zip") == displayed)
            // what the old code produced by taking the time again when writing
            #expect(FinderMenuItem.datedName("photos.zip", extension: "zip", at: writtenAt) != displayed)
        }

        @Test("An undated request keeps the plain name")
        func undatedNameIsUnchanged() throws {
            #expect(try AppUrl(url: url("compress"), scheme: scheme).archiveName("photos.zip", extension: "zip") == "photos.zip")
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
            #expect(throws: AppUrl.ParseError.invalidDate("../soon")) {
                try AppUrl(url: url("compress", extra: [URLQueryItem(name: "dated", value: "../soon")]), scheme: scheme)
            }
        }

        @Test("A path that doesn't decode to an absolute path rejects the whole request")
        func undecodablePathsAreRejected() {
            // values as the extension's inner encoding would leave them
            let requests: [(files: String, target: String)] = [
                ("/Users/me/ok.zip,/Users/me/bad%ZZ.zip", "/Users/me"),   // one bad file of two
                ("/Users/me/ok.zip", "/Users/me/%E0%A4%A"),               // truncated sequence in the target
                ("photos.zip", "/Users/me"),                               // relative: resolves against the working directory
                ("/Users/me/ok.zip", ""),                                  // empty target: the same
            ]
            for request in requests {
                #expect(throws: AppUrl.ParseError.missingFilesOrTarget) {
                    try AppUrl(url: url("compress", files: [], target: nil, extra: [
                        URLQueryItem(name: "files", value: request.files),
                        URLQueryItem(name: "target", value: request.target),
                    ]), scheme: scheme)
                }
            }
        }

        @Test("Paths with spaces, percent signs and accents come through unchanged")
        func unusualValidPathsSurvive() throws {
            let request = AppUrl(
                action: .compress,
                files: [URL(fileURLWithPath: "/Users/me/100% done/Füße.zip")],
                target: URL(fileURLWithPath: "/Users/me/100% done")
            )
            let url = try #require(request.url(scheme: scheme))
            #expect(try AppUrl(url: url, scheme: scheme) == request)
        }

        @Test("A comma in a file name doesn't split the path")
        func commaInFileName() throws {
            let request = AppUrl(
                action: .compress,
                files: [URL(fileURLWithPath: "/Users/me/a,b.zip"), URL(fileURLWithPath: "/Users/me/c.zip")],
                target: URL(fileURLWithPath: "/Users/me")
            )
            let url = try #require(request.url(scheme: scheme))
            #expect(try AppUrl(url: url, scheme: scheme) == request)
        }
    }
}
