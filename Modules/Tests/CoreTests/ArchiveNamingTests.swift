//
//  ArchiveNamingTests.swift
//  Modules
//
//  `ArchiveTypeDetector.getNameWithoutExtension(for:)` — the name of the folder
//  the "Extract to …" action creates. It classifies by *name* only
//  (`detectByExtension`), so every case here works on paths that need not exist;
//  the one fixture-backed test pins exactly that contract: a real spanned
//  terminal `.zip` must still be named from its name, not from its bytes.
//
//  Three branches to keep honest: compound (`tar.gz`), split volume
//  (`.z03`, `.zip.005`), plain format (`.zip`) — all case-insensitive matches
//  that must preserve the base name's own casing.
//

import Testing
import Foundation
@testable import Core

extension AllCoreTests {
    @MainActor struct ArchiveNamingTests {

        private let catalog = ArchiveTypeCatalog()

        /// The name the extract-to folder would get for `file`. The path is never
        /// read, so it does not have to exist.
        private func folderName(_ file: String) -> String {
            ArchiveTypeDetector(catalog: catalog)
                .getNameWithoutExtension(for: URL(fileURLWithPath: "/tmp/\(file)"))
        }

        private func zipDir() -> URL {
            Bundle.module.url(forResource: "zip", withExtension: nil)!
        }

        // MARK: - Plain format extensions

        @Test func plainExtensionStripped() {
            let cases = [
                "MyArchive.zip", "MyArchive.7z", "MyArchive.rar", "MyArchive.tar",
                "MyArchive.xz", "MyArchive.gz", "MyArchive.bz2", "MyArchive.z",
                "MyArchive.sit", "MyArchive.sitx", "MyArchive.zipx", "MyArchive.lzh",
                "MyArchive.iso", "MyArchive.dmg", "MyArchive.deb", "MyArchive.msi",
                // zip aliases — same format, so the same branch has to strip them
                "MyArchive.jar", "MyArchive.aar", "MyArchive.apk",
            ]
            for file in cases {
                #expect(folderName(file) == "MyArchive", "\(file)")
            }
        }

        /// Catalog-driven: a format added later gets naming coverage for free.
        @Test func everyCatalogFormatExtensionStripped() {
            for type in catalog.getAllTypes() {
                for ext in type.extensions {
                    #expect(folderName("MyArchive.\(ext)") == "MyArchive", "\(type.id): .\(ext)")
                    #expect(folderName("MyArchive.\(ext.uppercased())") == "MyArchive",
                            "\(type.id): .\(ext.uppercased())")
                }
            }
        }

        // MARK: - Compound extensions

        @Test func compoundExtensionStripped() {
            let cases = [
                "MyArchive.tar.gz", "MyArchive.tar.bz2", "MyArchive.tar.xz",
                "MyArchive.tar.lz4", "MyArchive.tar.Z", "MyArchive.tgz",
                "MyArchive.tbz2", "MyArchive.txz", "MyArchive.taz",
            ]
            for file in cases {
                #expect(folderName(file) == "MyArchive", "\(file)")
            }
        }

        @Test func everyCatalogCompoundExtensionStripped() {
            for composition in catalog.allCompositions() {
                for ext in composition.extensions {
                    #expect(folderName("MyArchive.\(ext)") == "MyArchive", ".\(ext)")
                    #expect(folderName("MyArchive.\(ext.uppercased())") == "MyArchive",
                            ".\(ext.uppercased())")
                }
            }
        }

        // MARK: - Split volume suffixes

        @Test func spannedVolumeSuffixStripped() {
            for file in ["MyArchive.z01", "MyArchive.z02", "MyArchive.z03",
                         "MyArchive.z10", "MyArchive.z99", "MyArchive.z100",
                         "MyArchive.z000001"] {
                #expect(folderName(file) == "MyArchive", "\(file)")
            }
        }

        @Test func numericVolumeSuffixStripped() {
            for file in ["MyArchive.zip.001", "MyArchive.zip.002", "MyArchive.zip.005",
                         "MyArchive.zip.0001", "MyArchive.zip.1234"] {
                #expect(folderName(file) == "MyArchive", "\(file)")
            }
        }

        /// Every part of one set must name the *same* folder — otherwise extracting
        /// two volumes of the same archive produces two folders.
        @Test func allPartsOfASetNameTheSameFolder() {
            for part in ["split_pk.z01", "split_pk.z02", "split_pk.zip"] {
                #expect(folderName(part) == "split_pk", "\(part)")
            }
            for part in ["split_7zz.zip.001", "split_7zz.zip.002", "split_7zz.zip.003"] {
                #expect(folderName(part) == "split_7zz", "\(part)")
            }
        }

        // MARK: - Casing

        @Test func stripIsCaseInsensitiveAndBaseKeepsItsCasing() {
            let cases = [
                ("MyArchive.Z03", "MyArchive"),
                ("MYARCHIVE.Z03", "MYARCHIVE"),
                ("MyArchive.ZIP.005", "MyArchive"),
                ("MYARCHIVE.Zip.005", "MYARCHIVE"),
                ("MyArchive.ZIP", "MyArchive"),
                ("MyArchive.TAR.GZ", "MyArchive"),
                // mixed case on a compound — only the trailing component upper
                ("MyArchive.tar.Z", "MyArchive"),
                ("MixedCase.TaR.gZ", "MixedCase"),
            ]
            for (file, expected) in cases {
                #expect(folderName(file) == expected, "\(file)")
            }
        }

        // MARK: - Dotted base names (the suffix regexes are `$`-anchored)

        @Test func onlyTheTrailingVolumeSuffixIsStripped() {
            let cases = [
                // dots inside the base survive
                ("My.Archive.z03", "My.Archive"),
                ("My.Archive.zip.007", "My.Archive"),
                // a volume-looking token earlier in the name is not eaten
                ("data.z01.backup.z02", "data.z01.backup"),
                ("v1.2.3.z01", "v1.2.3"),
                // a split part of a compound keeps the compound (the extract runs twice)
                ("MyArchive.tar.gz.z02", "MyArchive.tar.gz"),
            ]
            for (file, expected) in cases {
                #expect(folderName(file) == expected, "\(file)")
            }
        }

        // MARK: - Look-alikes that are not volumes

        @Test func volumeLookalikesAreNotStripped() {
            let cases = [
                // spanned needs 2+ digits, numeric needs 3+
                ("notes.z1", "notes.z1"),
                ("photo.zip.99", "photo.zip.99"),
                // numeric scheme is `.zip.NNN` only — a zip alias is not a volume
                ("app.apk.001", "app.apk.001"),
                ("MyArchive.tar.gz.001", "MyArchive.tar.gz.001"),
                // trailing plain extension wins; the earlier `.z01` stays in the base
                ("archive.z01.zip", "archive.z01"),
            ]
            for (file, expected) in cases {
                #expect(folderName(file) == expected, "\(file)")
            }
        }

        @Test func unknownNamesAreReturnedUnchanged() {
            for file in ["readme.txt", "README", "notes.markdown", "archive.z01.txt"] {
                #expect(folderName(file) == file, "\(file)")
            }
        }

        // MARK: - Name-only contract (no content probe)

        /// `split_pk.zip` is a *real* spanned terminal volume — `detect(for:)`
        /// recognizes it from the EOCD marker. Naming must not: it runs on
        /// `detectByExtension`, so the bare `.zip` is stripped as a plain zip.
        /// Switching this to `detect(for:)` would name the folder `split_pk.zip`,
        /// because no split pattern matches a bare `.zip`.
        @Test func bareSpannedVolumeIsNamedFromItsNameNotItsBytes() {
            let detector = ArchiveTypeDetector(catalog: catalog)
            let url = zipDir().appendingPathComponent("split_pk.zip")

            #expect(detector.detect(for: url)?.split?.scheme == "spanned")
            #expect(detector.getNameWithoutExtension(for: url) == "split_pk")
        }

        // MARK: - Tripwire

        /// Naming samples above are hand-written per scheme (a regex gives no
        /// sample name). A new split entry must arrive with its own cases.
        @Test func everySplitSchemeHasNamingSamples() {
            #expect(Set(catalog.allSplits().map(\.id)) == ["zip-spanned", "zip-numeric"])
        }
    }
}
