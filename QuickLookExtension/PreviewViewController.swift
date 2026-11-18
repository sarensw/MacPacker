//
//  PreviewViewController.swift
//  QuickLookExtension
//
//  Created by Stephan Arenswald on 03.10.25.
//

import ArchivePreviewUI
import Cocoa
import Core
import Quartz

/// QuickLook entry point. All of the preview UI and archive loading lives in the
/// shared `ArchivePreviewUI` module so the exact same code can be run and
/// debugged in-process via the main app's DEBUG harness.
class PreviewViewController: NSViewController, QLPreviewingController {
    private let preview = ArchivePreviewViewController()

    override func loadView() {
        addChild(preview)
        view = preview.view
    }

    func preparePreviewOfFile(at url: URL) async throws {
        // Here, not in the shared controller: the harness runs it in the app,
        // whose own files are not the earlier previews'.
        CacheCleaner.removeEarlierPreviews()
        try await preview.loadPreview(of: url)
    }
}
