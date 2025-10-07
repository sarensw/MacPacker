//
//  PreviewViewController.swift
//  QuickLookExtension
//
//  Created by Stephan Arenswald on 03.10.25.
//

import Cocoa
import OSLog
import os
import Quartz

enum ArchiveViewerColumn: String, CaseIterable {
    case name
    case compressedSize
    case uncompressedSize
    case modificationDate
    case posixPermissions

    var identifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(self.rawValue)
    }

    init?(identifier: NSUserInterfaceItemIdentifier) {
        self.init(rawValue: identifier.rawValue)
    }
}


enum QLLog {
    static let subsystem = "app.MacPacker.QuickLookExt"
    static let general = Logger(subsystem: subsystem, category: "general")
    static let drag    = Logger(subsystem: subsystem, category: "drag")
}

class PreviewViewController: NSViewController, QLPreviewingController {
    private let contentViewController = ContentViewController()
    
    override func loadView() {
        addChild(contentViewController)
        view = contentViewController.view
    }

    func preparePreviewOfFile(at url: URL) async throws {
        do {
            let e = try XadMasterHandler().listContents(of: url.path)
            let hierarchy = ArchiveHierarchy(entries: e)
            
            let archive = Archive(
                url: url,
                hierarchy: hierarchy
            )
            contentViewController.archive = archive
        } catch {
            QLLog.general.error("Failed to load archive at \(url.path)")
        }
        
        if let outlineView = (view as? NSScrollView)?.documentView as? NSOutlineView {
            outlineView.reloadData()
        }
    }
}
