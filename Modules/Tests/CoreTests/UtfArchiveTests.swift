//
//  UtfArchiveTests.swift
//  Modules
//
//  Created by Claude on 19.06.26.
//
//  Regression tests for archives that involve non-ASCII / UTF-8 names —
//  both the archive's own file name (`utf_你好.zip`, `папка.zip`) and the
//  names of the entries inside it (`utf_你好.txt`).
//
//  These used to fail with the 7-Zip engine: 7-Zip's load-time constructor
//  sets `g_ForceToUTF8` from the C locale, which is "C"/"POSIX" in a
//  GUI/test process, so filesystem paths got mangled (non-ASCII bytes turned
//  into '_'). Opening a UTF-named archive failed outright, and extracting a
//  UTF-named entry wrote it under the wrong name. The XAD engine was always
//  fine. The fix forces UTF-8 path handling in the 7-Zip bridge.
//

import Testing
import Foundation
@testable import Core

extension AllCoreTests {
    @MainActor struct UtfArchiveTests {

        // MARK: Open archives whose *file name* is non-ASCII

        @Test(arguments: ["utf_你好.zip", "папка.zip"])
        func loadUtfNamedArchive7Zip(_ name: String) async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "zip", withExtension: nil)!
            let url = folderURL.appendingPathComponent(name)

            #expect(FileManager.default.fileExists(atPath: url.path))

            state.open(url: url)
            try await state.openTask?.value

            #expect(state.error == nil)
            #expect(state.root != nil)
            #expect(state.entries.count > 0)
        }

        // Cross-check: the XAD engine was never affected by the locale issue.
        @Test(arguments: ["utf_你好.zip", "папка.zip"])
        func loadUtfNamedArchiveXad(_ name: String) async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelectorXad())
            let folderURL = Bundle.module.url(forResource: "zip", withExtension: nil)!
            let url = folderURL.appendingPathComponent(name)

            #expect(FileManager.default.fileExists(atPath: url.path))

            state.open(url: url)
            try await state.openTask?.value

            #expect(state.error == nil)
            #expect(state.root != nil)
            #expect(state.entries.count > 0)
        }

        // MARK: Extract an entry whose *name* is non-ASCII

        @Test func extractUtfNamedEntry7Zip() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "zip", withExtension: nil)!
            let url = folderURL.appendingPathComponent("utf_你好.zip")

            state.open(url: url)
            try await state.openTask?.value

            let entry = try #require(
                state.entries.values.first { $0.type == .file && $0.name == "utf_你好.txt" },
                "archive should expose a file entry named utf_你好.txt"
            )

            let extractedUrl = try await state.extractToTemp(item: entry)

            // The non-ASCII name must survive extraction to disk intact.
            #expect(extractedUrl.lastPathComponent == "utf_你好.txt")
            #expect(FileManager.default.fileExists(atPath: extractedUrl.path))
        }
    }
}
