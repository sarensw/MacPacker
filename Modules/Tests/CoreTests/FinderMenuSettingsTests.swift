//
//  FinderMenuSettingsTests.swift
//  Modules
//
//  `FinderMenuSettings` decides what the Finder context menu shows. Three
//  things can silently break it: an unwritten key must fall back to the item's
//  own default (a fresh extension has never seen the app's settings), each
//  entry must only show for a selection it can act on, and the dated archive
//  name must stay a valid file name that sorts by date.
//

import Foundation
import Testing
@testable import FinderMenu

extension AllCoreTests {
    struct FinderMenuSettingsTests {

        /// A defaults domain of its own, so the tests never read or write the
        /// real app group.
        private func scratchDefaults() -> UserDefaults {
            let suite = "FinderMenuSettingsTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            return defaults
        }

        /// Every entry switched on, so only the selection filters.
        private func everythingOn() -> UserDefaults {
            let defaults = scratchDefaults()
            for item in FinderMenuItem.allCases {
                defaults.set(true, forKey: FinderMenuSettings.key(for: item))
            }
            return defaults
        }

        @Test("An unwritten key falls back to the item's own default")
        func unwrittenKeysUseTheDefault() {
            let defaults = scratchDefaults()
            for item in FinderMenuItem.allCases {
                #expect(FinderMenuSettings.isEnabled(item, in: defaults) == item.isEnabledByDefault)
            }
            #expect(FinderMenuSettings.isCascaded(in: defaults))
        }

        @Test("The default menu is the lean set")
        func defaultSetIsLean() {
            #expect(FinderMenuSettings.visibleItems(files: 1, folders: 0, in: scratchDefaults()) == [
                .extractHere, .extractToChosenFolder, .compressToZip, .compressToDatedZip
            ])
        }

        @Test("A written key wins over the default, in both directions")
        func writtenKeysWin() {
            let defaults = scratchDefaults()

            defaults.set(false, forKey: FinderMenuSettings.key(for: .extractHere))
            defaults.set(true, forKey: FinderMenuSettings.key(for: .compressTo7z))
            defaults.set(false, forKey: FinderMenuSettings.cascadedKey)

            #expect(!FinderMenuSettings.isEnabled(.extractHere, in: defaults))
            #expect(FinderMenuSettings.isEnabled(.compressTo7z, in: defaults))
            #expect(!FinderMenuSettings.isCascaded(in: defaults))
        }

        @Test("A single folder gets the compress entries and its contents, no extract entries")
        func singleFolder() {
            #expect(FinderMenuSettings.visibleItems(files: 0, folders: 1, in: everythingOn()) == [
                .addToArchive, .compressToZip, .compressToDatedZip, .compressTo7z, .compressFolderContents
            ])
        }

        @Test("Several items get Compress Each, but not a folder's contents")
        func severalItems() {
            let visible = FinderMenuSettings.visibleItems(files: 2, folders: 1, in: everythingOn())
            #expect(visible.contains(.compressEachSeparately))
            #expect(!visible.contains(.compressFolderContents))
            #expect(visible.contains(.extractHere))
        }

        @Test("A single file never gets Compress Each")
        func singleFileHasNoCompressEach() {
            let visible = FinderMenuSettings.visibleItems(files: 1, folders: 0, in: everythingOn())
            #expect(!visible.contains(.compressEachSeparately))
        }

        @Test("The dated name keeps the extension and sorts by date")
        func datedName() throws {
            let utc = try #require(TimeZone(identifier: "UTC"))
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = utc
            let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 14, minute: 30, second: 5)))

            #expect(FinderMenuItem.datedName("photos.zip", extension: "zip", at: date, timeZone: utc) == "photos 2026-09-10 14.30.zip")
            #expect(FinderMenuItem.datedName("photos", extension: "zip", at: date, timeZone: utc) == "photos 2026-09-10 14.30.zip")
        }

        @Test("Only the extensions the menu produces pass as a format")
        func formatAllowlist() {
            #expect(FinderMenuItem.isArchiveExtension("zip"))
            #expect(FinderMenuItem.isArchiveExtension("7z"))
            for unsafe in ["", "rar", "..", "../zip", "zip/../../evil", "7z/x"] {
                #expect(!FinderMenuItem.isArchiveExtension(unsafe))
            }
        }

        @Test("Only the compress entries name an output format")
        func onlyCompressItemsCarryAnExtension() {
            #expect(FinderMenuItem.compressToZip.archiveExtension == "zip")
            #expect(FinderMenuItem.compressToDatedZip.archiveExtension == "zip")
            #expect(FinderMenuItem.compressTo7z.archiveExtension == "7z")
            for item in [FinderMenuItem.open, .extractHere, .extractToFolder, .extractToChosenFolder, .addToArchive] {
                #expect(item.archiveExtension == nil)
            }
        }
    }
}
