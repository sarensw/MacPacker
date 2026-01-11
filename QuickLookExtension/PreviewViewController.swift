//
//  PreviewViewController.swift
//  QuickLookExtension
//
//  Created by Stephan Arenswald on 03.10.25.
//

import Cocoa
import Core
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
        QLLog.general.debug("Previewing file at \(url.path)")
        
        let catalog = ArchiveTypeCatalog()
        let configStore = ArchiveEngineConfigStore(catalog: catalog)
        
        // We have to restrict the formats to their engines here because we can't call a subprocess
        // from within an extension. We can only support the formats enabled through xad and swc right now.
        // TODO: Add 7z as library instead of command line
        configStore.setSelectedEngine(.xad, for: "7zip")
        configStore.setSelectedEngine(.xad, for: "bzip2")
        configStore.setSelectedEngine(.xad, for: "cab")
        configStore.setSelectedEngine(.xad, for: "cpio")
        configStore.setSelectedEngine(.xad, for: "gzip")
        configStore.setSelectedEngine(.xad, for: "iso")
        configStore.setSelectedEngine(.xad, for: "lha")
        configStore.setSelectedEngine(.swc, for: "lz4")
        configStore.setSelectedEngine(.xad, for: "lzx")
        configStore.setSelectedEngine(.xad, for: "rar")
        configStore.setSelectedEngine(.xad, for: "rpm")
        configStore.setSelectedEngine(.xad, for: "sea")
        configStore.setSelectedEngine(.xad, for: "sit")
        configStore.setSelectedEngine(.xad, for: "sitx")
        configStore.setSelectedEngine(.xad, for: "tar")
        configStore.setSelectedEngine(.xad, for: "xar")
        configStore.setSelectedEngine(.xad, for: "xz")
        configStore.setSelectedEngine(.xad, for: "z")
        configStore.setSelectedEngine(.xad, for: "zip")
        configStore.setSelectedEngine(.xad, for: "zipx")
        
        let selector = ArchiveEngineSelector(catalog: catalog, configStore: configStore)
        let state = ArchiveState(catalog: catalog, engineSelector: selector)
        
        state.onStatusChange = { status in
            QLLog.general.debug("status: \(status.rawValue)")
            
            if status == .done {
                self.contentViewController.state = state
                if let outlineView = (self.view as? NSScrollView)?.documentView as? NSOutlineView {
                    outlineView.reloadData()
                }
            }
        }
        state.onStatusTextChange = { text in
            QLLog.general.debug("statusText: \(text ?? "nil")")
        }
        
        state.open(url: url)
    }
}
