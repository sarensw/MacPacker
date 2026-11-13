//
//  FinderServicesTests.swift
//  Modules
//
//  In iCloud Drive and other File Provider folders Finder shows no Finder
//  extension's menu, only the Services menu (#342). MacPacker's services stand
//  in for entries of its Finder menu: each sends what its entry sends, and
//  each is reached by the name Info.plist gives it.
//

import AppKit
import Foundation
import Testing
@testable import FinderMenu

extension AllCoreTests {
    @MainActor
    struct FinderServicesTests {

        /// Files in a folder of their own, as Finder's selection.
        private func selection(_ names: String...) throws -> [URL] {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("FinderServicesTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return try names.map { name in
                let file = folder.appendingPathComponent(name)
                try Data().write(to: file)
                return file
            }
        }

        /// Runs `service` as Finder does: the selection on a pasteboard.
        private func requests(
            _ service: (FinderServices, NSPasteboard) -> Void,
            for selection: [URL]
        ) -> [AppUrl] {
            var sent: [AppUrl] = []
            let services = FinderServices { sent += $0 }
            let pasteboard = NSPasteboard(name: .init("FinderServicesTests.\(UUID().uuidString)"))
            defer { pasteboard.releaseGlobally() }
            pasteboard.clearContents()
            pasteboard.writeObjects(selection.map { $0 as NSURL })
            service(services, pasteboard)
            return sent
        }

        @Test func extractExtractsEachArchiveNextToItself() throws {
            let archives = try selection("photos.zip") + selection("docs.7z")
            let sent = requests({ var error: NSString?; $0.extract($1, userData: nil, error: &error) }, for: archives)

            #expect(sent.allSatisfy { $0.action == .extractHere })
            let byFolder = Dictionary(uniqueKeysWithValues: sent.map { ($0.target, $0.files) })
            #expect(byFolder == [
                archives[0].deletingLastPathComponent(): [archives[0]],
                archives[1].deletingLastPathComponent(): [archives[1]],
            ])
        }

        @Test func compressCompressesTheSelectionNextToIt() throws {
            let items = try selection("notes.txt", "photo.jpg")
            let sent = requests({ var error: NSString?; $0.compress($1, userData: nil, error: &error) }, for: items)

            #expect(sent == [AppUrl(action: .compress, files: items, target: items[0].deletingLastPathComponent())])
        }

        @Test func createArchiveOpensANewArchiveWithTheSelection() throws {
            let items = try selection("notes.txt", "photo.jpg")
            let sent = requests({ var error: NSString?; $0.createArchive($1, userData: nil, error: &error) }, for: items)

            #expect(sent == [AppUrl(action: .addToArchive, files: items, target: items[0].deletingLastPathComponent())])
        }

        /// macOS looks a service's title up in `ServicesMenu.strings` by the
        /// title itself, as a release build has it: one changed in Info.plist
        /// alone shows in English in every language.
        @Test(arguments: ["MacPacker/Info.plist", "MacPacker/Info_Store.plist"])
        func everyServiceTitleIsTranslated(plist: String) throws {
            let repository = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
            let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: repository.appending(path: plist)), format: nil) as? [String: Any]
            let services = try #require(info?["NSServices"] as? [[String: Any]])
            let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: repository.appending(path: "MacPacker/ServicesMenu.xcstrings"))) as? [String: Any]
            let titles = try #require(catalog?["strings"] as? [String: [String: Any]])
            let languages = ["ar", "ca", "de", "el", "en", "es-MX", "fa", "fr", "hi", "it", "ja", "ko", "nl", "no", "pl", "pt-BR", "ru", "tr", "uk", "vi", "zh-Hans", "zh-TW"]

            for service in services {
                let menuItem = try #require(service["NSMenuItem"] as? [String: String])
                let title = try #require(menuItem["default"]).replacingOccurrences(of: "$(INFOPLIST_KEY_CFBundleDisplayName)", with: "MacPacker")
                let localizations = try #require(titles[title]?["localizations"] as? [String: Any], "\(title)")
                #expect(localizations.keys.sorted() == languages, "\(title)")
            }
        }

        /// AppKit calls `<NSMessage>:userData:error:` on the provider. A
        /// method renamed in code, or a service left out of one of the two
        /// plists, does nothing and says nothing.
        ///
        /// AppKit also brings the app to the front before it calls a service,
        /// unless `NSShouldActivateForServiceRequest` says no: that must be
        /// said for every service whose Finder menu entry leaves Finder in
        /// front (#279).
        @Test(arguments: ["MacPacker/Info.plist", "MacPacker/Info_Store.plist"])
        func everyServiceInInfoPlistReachesItsMethod(plist: String) throws {
            let file = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: plist)
            let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil) as? [String: Any]
            let services = try #require(info?["NSServices"] as? [[String: Any]])
            #expect(services.compactMap { $0["NSMessage"] as? String } == ["extract", "compress", "createArchive"])

            typealias Service = @convention(c) (AnyObject, Selector, NSPasteboard, NSString?, AutoreleasingUnsafeMutablePointer<NSString?>) -> Void
            for service in services {
                let message = try #require(service["NSMessage"] as? String)
                let selector = NSSelectorFromString("\(message):userData:error:")
                try #require(FinderServices.instancesRespond(to: selector), "\(message)")

                // called the way AppKit calls it
                let sent = requests({ services, pasteboard in
                    var error: NSString?
                    unsafeBitCast(services.method(for: selector), to: Service.self)(services, selector, pasteboard, nil, &error)
                }, for: try selection("photos.zip"))
                let action = try #require(sent.first?.action, "\(message)")
                let activates = service["NSShouldActivateForServiceRequest"] as? Bool ?? true
                #expect(activates == action.bringsAppToFront, "\(message)")
            }
        }
    }
}
