//
//  FinderSync.swift
//  FinderExtension
//
//  Created by Stephan Arenswald on 17.09.25.
//

import AppKit
import Cocoa
import FinderMenu
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
        // Finder renders this at the asset's own logical size and ignores anything
        // assigned to `size`, so the toolbar metrics are baked into the imageset:
        // a 24 pt canvas with the artwork inset to 20 pt, matching what Finder's
        // built-in items and other archivers ship.
        NSImage(named: "FinderToolbarIcon") ?? NSImage()
    }
    
    /// Whether the URL points at a directory. Uses the file system's
    /// `isDirectoryKey` rather than `hasDirectoryPath`, which only checks for a
    /// trailing slash and misclassifies folder URLs that lack one.
    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    /// When the menu was last built. The dated entry shows a name with this
    /// moment and sends it along, so the archive gets exactly that name.
    /// Finder builds menus and calls actions on the main thread.
    nonisolated(unsafe) private static var menuShownAt = Date()

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        Self.menuShownAt = Date()
        let allItems = FIFinderSyncController.default().selectedItemURLs() ?? []
        // archive actions only make sense for files; compression takes everything
        let fileItems = allItems.filter { !isDirectory($0) }
        log.debug("menu for \(allItems.count) item(s), \(fileItems.count) file(s)")

        guard !allItems.isEmpty else {
            if menuKind == .toolbarItemMenu {
                let menu = NSMenu(title: "??")
                let item = NSMenuItem(
                    title: String(localized: "Nothing selected", comment: "Disabled Finder toolbar menu item shown when no files are selected"),
                    action: nil,
                    keyEquivalent: ""
                )
                item.isEnabled = false
                menu.addItem(item)
                return menu
            }
            return NSMenu()
        }

#if DEBUG
        let title: String = "MacPacker Debug"
#else
        let title: String = "MacPacker"
#endif

        // The user picks the entries in Settings ▸ Extensions; the extension only
        // drops the ones the current selection cannot serve.
        let entries = FinderMenuSettings.visibleItems(
            files: fileItems.count,
            folders: allItems.count - fileItems.count
        )
        log.debug("showing \(entries.count) of \(FinderMenuItem.allCases.count) menu item(s)")
        guard !entries.isEmpty else { return NSMenu() }

        let macPackerSubmenu = NSMenu(title: title)
        for entry in entries {
            macPackerSubmenu.addItem(
                withTitle: menuTitle(for: entry, allItems: allItems, fileItems: fileItems),
                action: selector(for: entry),
                keyEquivalent: ""
            )
        }

        // The toolbar button is already labelled "MacPacker", and a flat menu
        // (7-Zip's "cascaded context menu" turned off) splices the entries
        // straight into Finder's own menu. Both want the bare list.
        if menuKind == .toolbarItemMenu || !FinderMenuSettings.isCascaded() {
            return macPackerSubmenu
        }

        let menu = NSMenu(title: "")
        let macPackerItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menu.setSubmenu(macPackerSubmenu, for: macPackerItem)
        menu.addItem(macPackerItem)

        return menu
    }

    private func selector(for item: FinderMenuItem) -> Selector {
        switch item {
        case .open: #selector(openArchive(_:))
        case .extractHere: #selector(extractHere(_:))
        case .extractToFolder: #selector(extractToFolder(_:))
        case .extractToChosenFolder: #selector(extractToChosenFolder(_:))
        case .addToArchive: #selector(addToArchive(_:))
        case .compressToZip: #selector(compressToZip(_:))
        case .compressToDatedZip: #selector(compressToDatedZip(_:))
        case .compressTo7z: #selector(compressTo7z(_:))
        case .compressEachSeparately: #selector(compressEachSeparately(_:))
        case .compressFolderContents: #selector(compressFolderContents(_:))
        }
    }

    private func menuTitle(for item: FinderMenuItem, allItems: [URL], fileItems: [URL]) -> String {
        switch item {
        case .open:
            let count = fileItems.count
            return String(localized: "Open \(count) Archive", comment: "Opens the archive in an archive window")

        case .extractHere:
            return String(localized: "Extract Here", comment: "Tell the user in the Finder context menu to extract the archive in the current directory as is")

        case .extractToFolder:
            // "Extract to "*\"" > if multiple archives files are selected
            // "Extract to defaultArchive\"" > if one archive is selected
            var folderName: String = ""
            if fileItems.count == 1 {
                // We're deleting the path extension here twice by purpose because compound archives
                // will be extracted twice. First decompressed, then extracted. And we need to show
                // the correct folder name
                //
                // Examples:
                // - archive.zip > archive
                // - archive.tar.gz > archive
                folderName = fileItems[0].deletingPathExtension().deletingPathExtension().lastPathComponent
            } else if fileItems.count > 1 {
                folderName = "*/"
            }
            return String(localized: "Extract to \"\(folderName)\"", comment: "Tell the user in the Finder context menu to extract the archive in the current directory. But there is a folder created based on the name of the archive where the archive is extracted to.")

        case .addToArchive:
            return String(localized: "Add to Archive…", comment: "Finder context menu: open a new-archive window pre-filled with the selection so name, format and compression can be picked")

        case .extractToChosenFolder:
            return String(localized: "Extract to…", comment: "Finder context menu: ask where to extract the selected archives, then extract them there")

        case .compressToZip, .compressToDatedZip, .compressTo7z:
            let ext = item.archiveExtension ?? "zip"
            var name = compressedArchiveName(for: allItems, pathExtension: ext)
            if item.isDated {
                name = FinderMenuItem.datedName(name, extension: ext, at: Self.menuShownAt)
            }
            return String(localized: "Compress to \"\(name)\"", comment: "Finder context menu: compress the selection directly to the named archive in the current directory")

        case .compressEachSeparately:
            return String(localized: "Compress Each Item Separately", comment: "Finder context menu: compress every selected item into its own zip next to it")

        case .compressFolderContents:
            let folder = allItems.first?.lastPathComponent ?? ""
            return String(localized: "Compress Contents of \"\(folder)\"", comment: "Finder context menu: compress what is inside the selected folder, without the folder itself, into a zip next to it")
        }
    }

    /// Same naming rule as the main app's compress handler: one item → its
    /// stem, several → the surrounding folder's name.
    private func compressedArchiveName(for items: [URL], pathExtension: String) -> String {
        if items.count == 1, let only = items.first {
            return only.deletingPathExtension().lastPathComponent + "." + pathExtension
        }
        let target = FIFinderSyncController.default().targetedURL()
        return (target?.lastPathComponent ?? "Archive") + "." + pathExtension
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
    
    private func communicateWithMainApp(item: FinderMenuItem) {
        communicateWithMainApp(action: item.action, format: item.archiveExtension, datedAt: item.isDated ? Self.menuShownAt : nil)
    }

    private func communicateWithMainApp(action: String, format: String? = nil, datedAt: Date? = nil) {
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
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "files", value: encodedPaths),
            URLQueryItem(name: "target", value: encodedTarget)
        ]
        if let format {
            queryItems.append(URLQueryItem(name: "format", value: format))
        }
        if let datedAt {
            queryItems.append(URLQueryItem(name: "dated", value: String(Int(datedAt.timeIntervalSince1970))))
        }
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
        communicateWithMainApp(item: .open)
    }

    @objc func extractHere(_ sender: Any?) {
        log.debug("Extract Here")
        communicateWithMainApp(item: .extractHere)
    }

    @objc func extractToFolder(_ sender: Any?) {
        log.debug("Extract to “%FOLDER%/”")
        communicateWithMainApp(item: .extractToFolder)
    }

    @objc func addToArchive(_ sender: Any?) {
        log.notice("Finder menu: Add to Archive…")
        communicateWithMainApp(item: .addToArchive)
    }

    @objc func compressToZip(_ sender: Any?) {
        log.notice("Finder menu: Compress to zip")
        communicateWithMainApp(item: .compressToZip)
    }

    @objc func compressTo7z(_ sender: Any?) {
        log.notice("Finder menu: Compress to 7z")
        communicateWithMainApp(item: .compressTo7z)
    }

    @objc func extractToChosenFolder(_ sender: Any?) {
        log.notice("Finder menu: Extract to…")
        communicateWithMainApp(item: .extractToChosenFolder)
    }

    @objc func compressToDatedZip(_ sender: Any?) {
        log.notice("Finder menu: Compress to dated zip")
        communicateWithMainApp(item: .compressToDatedZip)
    }

    @objc func compressEachSeparately(_ sender: Any?) {
        log.notice("Finder menu: Compress each item separately")
        communicateWithMainApp(item: .compressEachSeparately)
    }

    @objc func compressFolderContents(_ sender: Any?) {
        log.notice("Finder menu: Compress folder contents")
        communicateWithMainApp(item: .compressFolderContents)
    }

}

