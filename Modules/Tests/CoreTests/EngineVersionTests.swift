//
//  EngineVersionTests.swift
//  Modules
//
//  Created by Stephan Arenswald on 27.07.26.
//
//  Guard rails for the engine versions shown in the "Info on Engines" popover.
//  7-Zip and XAD report their own version at runtime -- these tests catch those
//  lookups silently breaking. SWCompression reports nothing, so its value is
//  hardcoded and checked here against the pin it claims to mirror.
//

import Foundation
import Testing
@testable import Core

extension AllCoreTests {
    struct EngineVersionTests {

        /// Repo root, derived from this file's location at compile time.
        /// `Bundle.module` is no help -- none of these files are test resources.
        private static var repoRoot: URL {
            URL(fileURLWithPath: #filePath)          // Modules/Tests/CoreTests/EngineVersionTests.swift
                .deletingLastPathComponent()         // Modules/Tests/CoreTests
                .deletingLastPathComponent()         // Modules/Tests
                .deletingLastPathComponent()         // Modules
                .deletingLastPathComponent()         // <repo>
        }

        @Test("7-Zip version comes from the vendored submodule")
        func sevenZipVersionMatchesVendoredSource() throws {
            let header = Self.repoRoot
                .appending(path: "Modules/Sources/CSevenZip/vendor/7zip/C/7zVersion.h")
            let source = try String(contentsOf: header, encoding: .utf8)

            let match = try #require(
                source.firstMatch(of: /#define\s+MY_VERSION_NUMBERS\s+"([^"]+)"/),
                "MY_VERSION_NUMBERS not found in \(header.path)"
            )

            #expect(ArchiveEngineType.`7zip`.libraryVersion == String(match.1))
        }

        @Test("XAD version resolves from the embedded framework bundle")
        func xadVersionResolvesFromFrameworkBundle() {
            // "—" is the fallback when the Info.plist lookup fails.
            #expect(ArchiveEngineType.xad.libraryVersion != "—")
        }

        @Test("SWCompression version matches the resolved package pin")
        func swcVersionMatchesResolvedPin() throws {
            // The app builds against the workspace Package.resolved, not Modules/.
            let resolved = Self.repoRoot
                .appending(path: "MacPacker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
            let data = try Data(contentsOf: resolved)

            struct Resolved: Decodable {
                struct Pin: Decodable {
                    struct State: Decodable { let version: String? }
                    let identity: String
                    let state: State
                }
                let pins: [Pin]
            }

            let pin = try #require(
                try JSONDecoder().decode(Resolved.self, from: data)
                    .pins.first { $0.identity == "swcompression" },
                "no swcompression pin in \(resolved.path)"
            )

            #expect(ArchiveEngineType.swc.libraryVersion == pin.state.version)
        }
    }
}
