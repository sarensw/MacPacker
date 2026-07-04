//
//  SplitArchiveTests.swift
//  Modules
//
//  Split / multi-volume archive support (7-Zip engine): detection, canonical
//  volume resolution, and open + extract from the resolved volume.
//
//  Fixtures (in the bundled `zip/` dir), both containing a single `lorem.txt`:
//   - spanned zip (Info-Zip `zip -s`): split_pk.z01, split_pk.z02, split_pk.zip
//   - numeric split (7-Zip volumes):   split_7zz.zip.001 … split_7zz.zip.003
//
//  These run unsandboxed, so they validate the detector/resolver/engine path;
//  the folder-access (sandbox) middleware is verified manually on a Release build.
//

import Testing
import Foundation
@testable import Core

extension AllCoreTests {
    @MainActor struct SplitArchiveTests {

        private func zipDir() -> URL {
            Bundle.module.url(forResource: "zip", withExtension: nil)!
        }

        private func newState() -> ArchiveState {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            // Unsandboxed tests can already read the folder, so grant unconditionally.
            state.folderAccessProvider = { _ in true }
            return state
        }

        private func names(_ state: ArchiveState) -> [String] {
            state.entries.values.map { $0.name }
        }

        /// Opens the given part *directly*. `ArchiveLoader.loadEntries` resolves the
        /// first volume itself (like it does for a compound), so handing it any part
        /// surfaces the whole archive.
        private func openPart(_ partName: String) async throws -> ArchiveState {
            let state = newState()
            state.open(url: zipDir().appendingPathComponent(partName))
            try await state.openTask?.value
            return state
        }

        // MARK: - Detection (the detector is the single "is this split?" authority)

        @Test func detectSpannedZipParts() {
            let detector = ArchiveTypeDetector(catalog: ArchiveTypeCatalog())
            for part in ["split_pk.z01", "split_pk.z02", "archive.z10"] {
                let result = detector.detect(for: URL(fileURLWithPath: "/x/\(part)"))
                #expect(result?.type.id == "zip", "\(part)")
                #expect(result?.split?.scheme == "spanned", "\(part)")
            }
        }

        @Test func detectNumericZipParts() {
            let detector = ArchiveTypeDetector(catalog: ArchiveTypeCatalog())
            for part in ["split_7zz.zip.001", "split_7zz.zip.003", "a.zip.123"] {
                let result = detector.detect(for: URL(fileURLWithPath: "/x/\(part)"))
                #expect(result?.type.id == "zip", "\(part)")
                #expect(result?.split?.scheme == "numeric", "\(part)")
            }
        }

        @Test func detectorReportsBareSpannedZip() {
            let detector = ArchiveTypeDetector(catalog: ArchiveTypeCatalog())
            let dir = zipDir()
            // The final `.zip` of a spanned set has no name hint — recognized from
            // the EOCD content marker (catalog-driven).
            #expect(detector.detect(for: dir.appendingPathComponent("split_pk.zip"))?.split?.scheme == "spanned")
            #expect(detector.detect(for: dir.appendingPathComponent("nestedFolders.zip"))?.split == nil)
        }

        @Test func catalogDeclaresZipSplits() throws {
            // Split detection *and* first-volume resolution are catalog data in the
            // top-level `splits` list; the engine only declares the capability.
            let catalog = ArchiveTypeCatalog()
            let zipSplits = catalog.allSplits().filter { $0.format == "zip" }
            #expect(Set(zipSplits.map(\.scheme)) == ["spanned", "numeric"])

            let spanned = try #require(zipSplits.first(where: { $0.scheme == "spanned" }))
            #expect(spanned.firstVolume.replacement == ".z01")
            // spanned carries a content marker (the EOCD) so a bare `.zip` is
            // recognized from its bytes; numeric is name-only, so no marker.
            #expect(spanned.marker != nil)
            let numeric = try #require(zipSplits.first(where: { $0.scheme == "numeric" }))
            #expect(numeric.marker == nil)

            // the default engine declares it can read split volumes
            let zip = try #require(catalog.getType(for: "zip"))
            let engine = try #require(zip.engines.first(where: { $0.default == true }))
            #expect(engine.capabilities.contains("splitVolumes"))
        }

        // MARK: - Window-identity label (catalog data; the manager applies it)

        @Test func splitsDeclareDedupLabels() throws {
            // The dedup label is catalog *data* — the window manager applies it (a
            // spanned `.z05` and the bare `.zip` both reduce to `<base>.zip`, numeric
            // parts to `<base>.zip.001`), so it isn't a Core method.
            let catalog = ArchiveTypeCatalog()
            let spanned = try #require(catalog.allSplits().first { $0.scheme == "spanned" })
            let numeric = try #require(catalog.allSplits().first { $0.scheme == "numeric" })
            #expect(spanned.label == ".zip")
            #expect(numeric.label == ".zip.001")
        }

        // MARK: - First volume: 7-Zip is pointed at the FIRST segment

        @Test func spannedResolvesToFirstVolume() throws {
            let dir = zipDir()
            let split = try #require(ArchiveTypeCatalog().allSplits().first { $0.scheme == "spanned" })
            for part in ["split_pk.z01", "split_pk.z02", "split_pk.zip"] {
                let entry = SplitVolumeResolver.firstVolume(
                    for: dir.appendingPathComponent(part), split: split)
                #expect(entry.lastPathComponent == "split_pk.z01", "\(part)")
            }
        }

        @Test func numericResolvesToFirstVolume() throws {
            let dir = zipDir()
            let split = try #require(ArchiveTypeCatalog().allSplits().first { $0.scheme == "numeric" })
            for part in ["split_7zz.zip.001", "split_7zz.zip.003"] {
                let entry = SplitVolumeResolver.firstVolume(
                    for: dir.appendingPathComponent(part), split: split)
                #expect(entry.lastPathComponent == "split_7zz.zip.001", "\(part)")
            }
        }

        // MARK: - End-to-end: opening ANY part surfaces the real file (lorem.txt)

        @Test func openSpannedZipViaAnyPart() async throws {
            for part in ["split_pk.z01", "split_pk.z02", "split_pk.zip"] {
                let state = try await openPart(part)
                #expect(state.error == nil, "opening \(part)")
                #expect(state.type?.id == "zip", "opening \(part)")
                #expect(names(state).contains("lorem.txt"), "opening \(part) → names=\(names(state))")
                // window identity is the first volume, whichever part was opened
                #expect(state.url?.lastPathComponent == "split_pk.z01", "opening \(part)")
                // title is the reassembled set name, not the specific part
                #expect(state.name == "split_pk.zip", "opening \(part)")
            }
        }

        @Test func openNumericSplitViaAnyPart() async throws {
            for part in ["split_7zz.zip.001", "split_7zz.zip.002", "split_7zz.zip.003"] {
                let state = try await openPart(part)
                #expect(state.error == nil, "opening \(part)")
                #expect(names(state).contains("lorem.txt"), "opening \(part) → names=\(names(state))")
                #expect(state.url?.lastPathComponent == "split_7zz.zip.001", "opening \(part)")
                #expect(state.name == "split_7zz.zip", "opening \(part)")
            }
        }

        // MARK: - Extraction reads across volumes

        @Test func extractSpannedZip() async throws {
            let state = try await openPart("split_pk.z02")
            let item = try #require(state.entries.values.first { $0.name == "lorem.txt" })
            let extractedUrl = try await state.extractToTemp(item: item)
            #expect(FileManager.default.fileExists(atPath: extractedUrl.path))
        }

        @Test func extractNumericSplit() async throws {
            let state = try await openPart("split_7zz.zip.003")
            let item = try #require(state.entries.values.first { $0.name == "lorem.txt" })
            let extractedUrl = try await state.extractToTemp(item: item)
            #expect(FileManager.default.fileExists(atPath: extractedUrl.path))
        }
    }
}
