//
//  FinderSync.swift
//  FinderExtension
//
//  Created by Stephan Arenswald on 17.09.25.
//

import AppKit
import Cocoa
import FinderSync
import Foundation
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "finder")

extension Bundle {

    public static var appRootURL: URL {
        var components = main.bundleURL.path.split(separator: "/")

        func isMainApp(_ comp: Substring) -> Bool {
            comp.hasSuffix(".app")// && !comp.hasPrefix("MacPacker")
        }

        if let index = components.lastIndex(where: isMainApp) {
            components.removeLast((components.count - 1) - index)
            return URL(fileURLWithPath: "/" + components.joined(separator: "/"))
        }

        return Bundle.main.bundleURL
    }

    public static var runnerAppURL: URL {
        appRootURL.appendingPathComponent("Contents/Applications/MacPacker.app")
    }

}

class FinderSync: FIFinderSync {
    private let mainAppBundleId = "com.sarensx.MacPacker"

    /// The main app's custom URL scheme, read from this extension's Info.plist so a
    /// Debug extension talks to the Debug app (app.macpacker.debug) and Release to Release.
    private let appScheme = Bundle.main.object(forInfoDictionaryKey: "MacPackerURLScheme") as? String ?? ""
    
    var baseFolderUrl = FileManager.default.homeDirectoryForCurrentUser
    var documentsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    
    override init() {
        super.init()
        
        tb.start()
        log.debug("FinderSync() launched from \(Bundle.main.bundlePath as NSString)")
        
        // Set up the directory we are syncing.
        let syncUrls: Set<URL> = [
            self.baseFolderUrl,
            URL(fileURLWithPath: "/Users/\(ProcessInfo.processInfo.userName)")
        ]
        FIFinderSyncController.default().directoryURLs = syncUrls
        log.debug("Initializing on...")
        for syncUrl in syncUrls {
            log.debug("\t\(syncUrl.path)")
        }
    }
    
    // MARK: - Primary Finder Sync protocol methods
    
    override func beginObservingDirectory(at url: URL) {
        // The user is now seeing the container's contents.
        // If they see it in more than one view at a time, we're only told once.
        log.debug("beginObservingDirectoryAtURL: \(url.path as NSString)")
    }
    
    
    override func endObservingDirectory(at url: URL) {
        // The user is no longer seeing the container's contents.
        log.debug("endObservingDirectoryAtURL: \(url.path as NSString)")
    }
    
    override func requestBadgeIdentifier(for url: URL) {
        log.debug("requestBadgeIdentifierForURL: \(url.path as NSString)")
    }
    
    // MARK: - Menu and toolbar item support
    
    override var toolbarItemName: String {
        return "MacPacker"
    }
    
    override var toolbarItemToolTip: String {
        return "MacPacker"
    }
    
    override var toolbarItemImage: NSImage {
        let img = NSImage(named: "AppIcon_MacPacker") ?? NSImage()
        img.size = NSSize(width: 18, height: 18)
        return img
    }
    
    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        // we're removing all urls that are folders until we support compression
        log.debug(String(describing: FIFinderSyncController.default().selectedItemURLs()))
        for item in FIFinderSyncController.default().selectedItemURLs() ?? [] {
            if item.hasDirectoryPath {
                log.debug("Removing \(item.absoluteString)")
            }
        }
        let selecteditems = FIFinderSyncController.default().selectedItemURLs()?.filter({ !$0.hasDirectoryPath }) ?? []
        log.debug(String(describing: selecteditems))
        
        if selecteditems.count > 0 // let selecteditems = FIFinderSyncController.default().selectedItemURLs()?.filter({ !$0.hasDirectoryPath })
        {
            log.debug("Creating menu for \(selecteditems[0].absoluteString), isDir? \(selecteditems[0].hasDirectoryPath)")
            // if all items are folders then ignore for now until we
            // actually support compression
            
            
            let count = selecteditems.count
            
            let menu = NSMenu(title: "")
            
            // Submenu for MacPacker
            let macPackerItem = NSMenuItem(title: "MacPacker", action: nil, keyEquivalent: "")
            let macPackerSubmenu = NSMenu(title: "MacPacker")
            
            // Open
            macPackerSubmenu.addItem(withTitle: String(localized: "Open \(count) Archive", comment: "Opens the archive in an archive window"),
                                     action: #selector(openArchive(_:)),
                                     keyEquivalent: "")
            
//            macPackerSubmenu.addItem(withTitle: "Extract files…",
//                                     action: #selector(extractFiles(_:)),
//                                     keyEquivalent: "")
            macPackerSubmenu.addItem(withTitle: NSLocalizedString("Extract Here", comment: "Tell the user in the Finder context menu to extract the archive in the current directory as is"),
                                     action: #selector(extractHere(_:)),
                                     keyEquivalent: "")
            
            // "Extract to "*\"" > if multiple archives files are selected
            // "Extract to defaultArchive\"" > if one archive is selected
            var folderName: String = ""
            if selecteditems.count == 1 {
                // We're deleting the path extension here twice by purpose because compound archives
                // will be extracted twice. First decompressed, then extracted. And we need to show
                // the correct folder name
                //
                // Examples:
                // - archive.zip > archive
                // - archive.tar.gz > archive
                folderName = selecteditems[0].deletingPathExtension().deletingPathExtension().lastPathComponent
            } else if selecteditems.count > 1 {
                folderName = "*/"
            }
            macPackerSubmenu.addItem(withTitle: String(localized: "Extract to \"\(folderName)\"", comment: "Tell the user in the Finder context menu to extract the archive in the current directory. But there is a folder created based on the name of the archive where the archive is extracted to."),
                                     action: #selector(extractToFolder(_:)),
                                     keyEquivalent: "")
            
            
            //        // Compression section
            //        let compressionHeader = NSMenuItem(title: "Compression", action: nil, keyEquivalent: "")
            //        compressionHeader.isEnabled = false
            //        macPackerSubmenu.addItem(compressionHeader)
            //
            //        macPackerSubmenu.addItem(withTitle: "Add to Archive…",
            //                                 action: #selector(addToArchive(_:)),
            //                                 keyEquivalent: "")
            //        macPackerSubmenu.addItem(withTitle: "Add to “%FILENAME%.7z”",
            //                                 action: #selector(addTo7z(_:)),
            //                                 keyEquivalent: "")
            //        macPackerSubmenu.addItem(withTitle: "Add to “%FILENAME%.zip”",
            //                                 action: #selector(addToZip(_:)),
            //                                 keyEquivalent: "")
            //
            //        // Extra section
            //        let extraHeader = NSMenuItem(title: "Other", action: nil, keyEquivalent: "")
            //        extraHeader.isEnabled = false
            //        macPackerSubmenu.addItem(extraHeader)
            //
            //        macPackerSubmenu.addItem(withTitle: "Test Archive",
            //                                 action: #selector(testArchive(_:)),
            //                                 keyEquivalent: "")
            
            // Attach submenu
            if menuKind == .toolbarItemMenu {
                return macPackerSubmenu
            }
            
            menu.setSubmenu(macPackerSubmenu, for: macPackerItem)
            menu.addItem(macPackerItem)
            
            return menu
        }
        
        if menuKind == .toolbarItemMenu {
            let menu = NSMenu(title: "??")
            let item = NSMenuItem(title: "..no archive(s) selected..", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return menu
        }
        
        return NSMenu()
    }

    
    @IBAction func sampleAction(_ sender: AnyObject?) {
        let target = FIFinderSyncController.default().targetedURL()
        let items = FIFinderSyncController.default().selectedItemURLs()
        
        let item = sender as! NSMenuItem
        NSLog("sampleAction: menu item: %@, target = %@, items = ", item.title as NSString, target!.path as NSString)
        for obj in items! {
            NSLog("    %@", obj.path as NSString)
        }
    }
    
    // MARK: - Actions
    
    private func communicateWithMainApp(action: String) {
        log.notice("Finder action '\(action)' requested", context: ["scheme": appScheme])
        if appScheme.isEmpty {
            log.error("MacPackerURLScheme missing from the extension's Info.plist — cannot reach the main app")
        }

        guard let items = FIFinderSyncController.default().selectedItemURLs() else {
            log.error("No items selected for action '\(action)'")
            return
        }

        log.notice("Encoding \(items.count) item(s) for '\(action)'",
                   context: ["first": items.first?.lastPathComponent ?? "-"])
        let paths = items.map { $0.path }.joined(separator: ",")
        guard let encodedPaths = paths.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            log.error("Failed to percent-encode the file paths")
            return
        }
        guard let encodedTarget = FIFinderSyncController.default().targetedURL()?.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            log.error("Failed to encode the target url (no targetedURL?)")
            return
        }

        var urlComponents = URLComponents(string: "\(appScheme)://\(action)")
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "files", value: encodedPaths),
            URLQueryItem(name: "target", value: encodedTarget)
        ]
        urlComponents?.queryItems = queryItems

        guard let url = urlComponents?.url else {
            log.error("Failed to build the app URL for action '\(action)'")
            return
        }

        log.notice("Opening main app for '\(action)'", context: ["url": url.absoluteString])
        let opened = NSWorkspace.shared.open(url)
        if opened {
            log.notice("Handed '\(action)' off to the main app")
        } else {
            log.error("NSWorkspace could not open \(url.absoluteString) — is the '\(appScheme)' scheme registered to MacPacker?")
        }
    }

    @objc func openArchive(_ sender: Any?) {
        log.notice("Finder menu: Open archive")
        communicateWithMainApp(action: "open")
    }

    @objc func extractFiles(_ sender: Any?) {
        communicateWithMainApp(action: "extractFiles")
        log.debug("Extract Files…")
    }

    @objc func extractHere(_ sender: Any?) {
        communicateWithMainApp(action: "extractHere")
        log.debug("Extract Here")
    }

    @objc func extractToFolder(_ sender: Any?) {
        communicateWithMainApp(action: "extractToFolder")
        log.debug("Extract to “%FOLDER%/”")
    }

    @objc func addToArchive(_ sender: Any?) {
        log.debug("Add to Archive…")
    }

    @objc func addTo7z(_ sender: Any?) {
        log.debug("Add to “%FILENAME%.7z”")
    }

    @objc func addToZip(_ sender: Any?) {
        log.debug("Add to “%FILENAME%.zip”")
    }

    @objc func testArchive(_ sender: Any?) {
        log.debug("Test Archive")
    }

}

