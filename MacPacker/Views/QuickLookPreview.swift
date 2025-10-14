//
//  QuickLookPreview.swift
//  MacPacker
//
//  Created by sonnet (gotta be honest) on 14.10.25.
//

import SwiftUI
import Quartz

/// A SwiftUI view that provides QuickLook preview functionality using the system's QLPreviewPanel
struct QuickLookPreview: NSViewControllerRepresentable {
    let urls: [URL]
    let currentIndex: Int
    
    init(url: URL) {
        self.urls = [url]
        self.currentIndex = 0
    }
    
    init(urls: [URL], currentIndex: Int = 0) {
        self.urls = urls
        self.currentIndex = currentIndex
    }
    
    func makeNSViewController(context: Context) -> QuickLookPreviewController {
        let controller = QuickLookPreviewController()
        controller.urls = urls
        controller.currentIndex = currentIndex
        return controller
    }
    
    func updateNSViewController(_ nsViewController: QuickLookPreviewController, context: Context) {
        nsViewController.urls = urls
        nsViewController.currentIndex = currentIndex
        nsViewController.reloadData()
    }
}

/// NSViewController that manages the QuickLook preview
class QuickLookPreviewController: NSViewController, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    var urls: [URL] = []
    var currentIndex: Int = 0
    
    private var previewView: QLPreviewView?
    private var keyDownMonitor: Any?
    
    override func loadView() {
        let previewView = QLPreviewView(frame: .zero, style: .normal)
        previewView?.autostarts = true
        self.previewView = previewView
        self.view = previewView ?? NSView()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        reloadData()
        setupKeyMonitor()
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear()
        removeKeyMonitor()
    }
    
    private func setupKeyMonitor() {
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Space key (keyCode 49) or Escape key (keyCode 53)
            if event.keyCode == 49 || event.keyCode == 53 {
                self?.view.window?.performClose(nil)
                return nil // Swallow the event
            }
            return event
        }
    }
    
    private func removeKeyMonitor() {
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
    }
    
    func reloadData() {
        guard !urls.isEmpty else { return }
        previewView?.previewItem = urls[currentIndex] as QLPreviewItem
    }
    
    // MARK: - QLPreviewPanelDataSource
    
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return urls.count
    }
    
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard index >= 0 && index < urls.count else { return nil }
        return urls[index] as QLPreviewItem
    }
}
