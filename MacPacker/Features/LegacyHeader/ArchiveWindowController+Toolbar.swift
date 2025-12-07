//
//  Toolbar.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 20.10.25.
//
//  This extension is only valid for macOS 13 support. Starting
//  with macOS 14, we're relying on the .toolbar() view modifier
//  to render a SwiftUI based toolbar.
//

import AppKit
import SwiftUI

extension NSToolbarItem.Identifier {
    static let preview = NSToolbarItem.Identifier("preview")
    static let extractSelected = NSToolbarItem.Identifier("extractSelected")
    static let extractAll = NSToolbarItem.Identifier("extractAll")
    static let more = NSToolbarItem.Identifier("more")
}

extension ArchiveWindowController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.preview, .extractSelected, .extractAll, .more]
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.preview, .extractSelected, .extractAll, .more]
    }
    
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
            
        case .preview: // preview selected item
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = NSLocalizedString("Preview", comment: "Button in the tooblar that allows the user to preview the selected file.")
            item.image = NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: "")
            item.action = #selector(previewSelected)
            item.isBordered = true
            return item
            
        case .extractSelected: // extract the selected item
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = NSLocalizedString("Extract selected", comment: "Button in the tooblar that allows the user to extract the selected files.")
            item.image = NSImage(named: "custom.document.badge.arrow.down")
            item.action = #selector(extractSelected)
            item.isBordered = true
            return item
            
        case .extractAll: // extract the full archive
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = NSLocalizedString("Extract archive", comment: "Button in the toolbar that allows the user to extract the full archive to a target directory.")
            item.image = NSImage(named: "custom.shippingbox.badge.arrow.down")
            item.action = #selector(extractAll)
            item.isBordered = true
            return item
            
        case .more: // the more menu
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            item.label = NSLocalizedString("More", comment: "The 'More' menu in the archive window")
            item.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "")
            item.menu = buildMoreMenu()
            return item
            
        default:
            return nil
        }
    }
    
    //
    // MARK: Drop down menu builders
    //
    
    func buildMoreMenu() -> NSMenu {
        let menu = NSMenu()
        
        // Settings
        let settingsItem = NSMenuItem()
        settingsItem.title = NSLocalizedString("Settings...", comment: "Used to open the settings/preferences window")
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        settingsItem.action = Selector(("showSettingsWindow:"))
        menu.addItem(settingsItem)
        
        menu.addItem(.separator())
        
        // Archive info
        let archiveInfoItem = NSMenuItem(
            title: NSLocalizedString("Archive info", comment: "Used to open Quick Look feature for the current archive file"),
            action: #selector(showArchiveInfoWindow),
            keyEquivalent: "")
        archiveInfoItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(archiveInfoItem)
        
        menu.addItem(.separator())
        
        // Send a smile menu
        let sendASmileMenuItem = NSMenuItem(
            title: NSLocalizedString("Send a smile", comment: "This is the menu in the 'More' menu of the archive window to give customers a hint on how to support the developer. The user has the option to open the MacPacker repository on GitHub or leave a review in the App Store."),
            action: nil,
            keyEquivalent: "")
        sendASmileMenuItem.image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: nil)
        sendASmileMenuItem.submenu = buildSendASmileMenu()
        menu.addItem(sendASmileMenuItem)
        
        // Go here to... menu
        let goHereToMenuItem = NSMenuItem(
            title: NSLocalizedString("Go here to ...", comment: "This is the menu in the 'More' menu of the archive window to give customers a hint what they can do to reach the dev. A submenu will open with links to GitHub, a bug report form, and a mail to the developer."),
            action: nil,
            keyEquivalent: "")
        goHereToMenuItem.image = NSImage(systemSymbolName: "exclamationmark.bubble", accessibilityDescription: nil)
        goHereToMenuItem.submenu = buildGoHereToMenu()
        menu.addItem(goHereToMenuItem)
        
        menu.addItem(.separator())
        
        // More apps menu
        let moreAppsMenu = NSMenuItem(
            title: NSLocalizedString("More Apps", comment: "Hint to the user that the submenu contains links for more apps that they might like."),
            action: nil,
            keyEquivalent: "")
        moreAppsMenu.image = NSImage(systemSymbolName: "plus.square.dashed", accessibilityDescription: nil)
        moreAppsMenu.submenu = buildMoreAppsMenu()
        menu.addItem(moreAppsMenu)
        
        // website
        let websiteItem = NSMenuItem(
            title: NSLocalizedString("Website", comment: "Hint to the user that the button links to the app's website."),
            action: #selector(visitWebsite),
            keyEquivalent: "")
        websiteItem.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
        menu.addItem(websiteItem)
        
        // github
        let githubItem = NSMenuItem(
            title: Constants.otherAppGitHub,
            action: #selector(visitGitHub),
            keyEquivalent: "")
        githubItem.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
        menu.addItem(githubItem)
        
        // about MacPacker window
        let aboutItem = NSMenuItem(
            title: NSLocalizedString("About \(Bundle.main.appName)", comment: ""),
            action: #selector(showAboutPanel),
            keyEquivalent: "")
        aboutItem.image = NSImage(systemSymbolName: "info.square", accessibilityDescription: nil)
        menu.addItem(aboutItem)
        
        return menu
    }
    
    func buildSendASmileMenu() -> NSMenu {
        let menu = NSMenu()
        
        let starItem = NSMenuItem(
            title: NSLocalizedString("Star the repository on GitHub", comment: "Opens the GitHub page of the MacPacker repository for the user to star it."),
            action: #selector(visitGitHub),
            keyEquivalent: "")
        menu.addItem(starItem)
        
        #if STORE
        let writeReviewItem = NSMenuItem(
            title: NSLocalizedString("Leave a review in the App Store", comment: "Opens the App Store review page for the MacPacker app for the user to write a review."),
            action: #selector(writeReview),
            keyEquivalent: "")
        menu.addItem(writeReviewItem)
        #endif
        
        return menu
    }
    
    func buildGoHereToMenu() -> NSMenu {
        let menu = NSMenu()
        
        // request a feature
        let requestFeatureItem = NSMenuItem(
            title: NSLocalizedString("... request a Feature", comment: "This is the second part of the text 'Go here to ...'. It is used in the archive window 'More' menu and shall give users a hint about the secondary options to reach out to the dev."),
            action: #selector(requestFeature),
            keyEquivalent: "")
        requestFeatureItem.image = NSImage(systemSymbolName: "shippingbox", accessibilityDescription: nil)
        menu.addItem(requestFeatureItem)
        
        // raise a bug
        let raiseBugItem = NSMenuItem(
            title: NSLocalizedString("... raise a Bug", comment: "This is the second part of the text 'Go here to ...'. It is used in the archive window 'More' menu and shall give users a hint about the secondary options to reach out to the dev."),
            action: #selector(raiseBug),
            keyEquivalent: "")
        raiseBugItem.image = NSImage(systemSymbolName: "ladybug", accessibilityDescription: nil)
        menu.addItem(raiseBugItem)
        
        // send a mail
        let sendMailItem = NSMenuItem(
            title: NSLocalizedString("... send a mail to \(Constants.supportMail)", comment: "This is the second part of the text 'Go here to ...'. It is used in the archive window 'More' menu and shall give users a hint about the secondary options to reach out to the dev."),
            action: #selector(sendMail),
            keyEquivalent: "")
        sendMailItem.image = NSImage(systemSymbolName: "mail", accessibilityDescription: nil)
        menu.addItem(sendMailItem)
        
        return menu
    }
    
    func buildMoreAppsMenu() -> NSMenu {
        let menu = NSMenu()
        
        let fileFilletItem = NSMenuItem(
            title: Constants.otherAppFileFillet,
            action: #selector(openFileFilletWebsite),
            keyEquivalent: "")
        fileFilletItem.image = .menuIcon(named: "FileFillet", pointSize: 16)
        menu.addItem(fileFilletItem)
        
        return menu
    }
    
    //
    // MARK: Toolbar button actions
    //
    
    @objc func previewSelected() {
        archiveState.updateSelectedItemForQuickLook()
    }
    
    @objc func extractSelected() {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [.folder]
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.begin { response in
            if response == .OK,
               let destinationURL = openPanel.url {
                self.archiveState.extract(
                    items: self.archiveState.selectedItems,
                    to: destinationURL)
            }
        }
    }
    
    @objc func extractAll() {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [.folder]
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.begin { response in
            if response == .OK,
               let destinationURL = openPanel.url {
                self.archiveState.extract(
                    to: destinationURL)
            }
        }
    }
    
    @objc func showSettingsWindow() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
    
    @objc func showArchiveInfoWindow() {
        if let url = archiveState.url {
            contentService.openGetInfoWnd(for: [url])
        }
    }
    
    @objc func writeReview() {
        if let url = URL(string: "https://apps.apple.com/app/id6473273874?action=write-review") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func requestFeature() {
        if let url = URL(string: "https://github.com/sarensw/MacPacker/issues/new?assignees=&labels=enhancement&projects=&template=&title=") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func raiseBug() {
        if let url = URL(string: "https://github.com/sarensw/MacPacker/issues/new?assignees=&labels=bug&projects=&template=bug_report.md&title=") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func sendMail() {
        if let url = URL(string: "mailto:\(Constants.supportMail)") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func openFileFilletWebsite() {
        if let url = URL(string: "https://filefillet.com/?utm_source=macpacker&utm_content=moremenu&utm_medium=ui") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func visitWebsite() {
        if let url = URL(string: "https://macpacker.app/?utm_source=macpacker&utm_content=moremenu&utm_medium=ui") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func visitGitHub() {
        if let url = URL(string: "https://github.com/sarensw/MacPacker/") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func showAboutPanel() {
        appDelegate.openAboutWindow()
    }
}
