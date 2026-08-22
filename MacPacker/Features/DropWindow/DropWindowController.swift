//
//  DropWindowController.swift
//  MacPacker
//
//  A floating panel, not a document window: it stays above what you are working
//  in and follows you across spaces, so Finder can drag onto it directly.
//

import AppKit
import Core
import Swift7zip
import SwiftUI
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "dropwindow")

@MainActor
final class DropWindowController {
    private var panel: NSPanel?
    private let compressor: DropCompressor

    init(compressor: DropCompressor) {
        self.compressor = compressor
    }

    /// Creates the panel on first use; later calls just bring it forward.
    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        // the saved display may have been unplugged since
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            panel.center()
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        log.notice("Drop window shown", context: [
            "frame": NSStringFromRect(panel.frame),
            "visible": "\(panel.isVisible)"
        ])
    }

    func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
            log.notice("Drop window hidden")
        } else {
            show()
        }
    }

    /// What `-DropWindow 1 -AddFiles a,b,c` calls: the whole path (grant, naming,
    /// write) drivable from a script without a real drag.
    @discardableResult
    func compress(files: [URL]) -> DropJob? {
        compressor.compress(files: files, options: CompressSettings.current)
    }

    private func makePanel() -> NSPanel {
        let hostingView = NSHostingView(rootView: DropWindowView(compressor: compressor))
        hostingView.frame.size = hostingView.fittingSize

        let panel = DropPanel(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // set but not drawn — the Window menu and accessibility still read it
        panel.title = String(localized: "Quick Compress", comment: "Title of the quick-compress window, the small floating window that compresses whatever is dropped on it. Also the title of the compress section on the start page.")
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        // Required: `mouseDownCanMoveWindow` only lets a view opt *out*. Controls
        // opt out individually — see `WindowDragArea`.
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        // there while you work somewhere else
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // accessory-window look: the system material behind a transparent window
        panel.isOpaque = false
        panel.backgroundColor = .clear
        let glass = NSVisualEffectView()
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.frame = NSRect(origin: .zero, size: hostingView.fittingSize)
        // Constraints, not a mask: only a constraint chain carries the hosting
        // view's size out to the glass wrapper. With a mask the window keeps its
        // birth height and clips the options away.
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: glass.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
        ])
        panel.contentView = glass

        // default is true, which would leave `panel` pointing at freed memory
        panel.isReleasedWhenClosed = false

        // the content sizes itself; the panel only has to remember where it was
        panel.setFrameAutosaveName("DropWindow")
        // A restored frame can be off every current screen, which looks exactly
        // like the window failing to open. Centre it instead.
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(panel.frame) }
        if !onScreen || panel.frame.origin == .zero { panel.center() }

        // Format and pin sit in the titlebar as plain content, not as toolbar
        // items: a toolbar brings its own background and separator, which is
        // exactly what this window is trying not to have.
        let controls = NSTitlebarAccessoryViewController()
        controls.layoutAttribute = .trailing
        let controlsView = NSHostingView(rootView: HStack(spacing: 10) {
            CompressFormatMenu()
            CompressPinButton { [weak self] floats in
                self?.panel?.level = floats ? .floating : .normal
            }
        }
            .padding(.trailing, 12))
        controlsView.frame.size = controlsView.fittingSize
        controls.view = controlsView
        panel.addTitlebarAccessoryViewController(controls)

        panel.level = floatsAboveOtherWindows ? .floating : .normal
        return panel
    }

    private var floatsAboveOtherWindows: Bool {
        UserDefaults.standard.bool(forKey: Keys.dropWindowFloats)
    }
}

/// The quick-compress window.
///
/// An NSWindow's origin is its *bottom* left, so content-driven growth pushes the
/// titlebar upwards — the options open downwards while the window slides up to
/// meet them. Pinning the top edge leaves one motion: the bottom moving down.
final class DropPanel: NSPanel {
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var rect = frameRect
        // only content-driven resizes; a user drag moves the origin too
        if rect.height != frame.height, rect.origin == frame.origin {
            rect.origin.y = frame.maxY - rect.height
        }
        super.setFrame(rect, display: flag)
    }
}
