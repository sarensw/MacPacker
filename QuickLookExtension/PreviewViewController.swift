//
//  PreviewViewController.swift
//  QuickLookExtension
//
//  Created by Stephan Arenswald on 03.10.25.
//

import ArchivePreviewUI
import Cocoa
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
        try await preview.loadPreview(of: url)
    }
}
