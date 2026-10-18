//
//  NSImage+AppIcon.swift
//  MacPacker
//
//  The app icon for drawing inside MacPacker's own windows.
//

import AppKit

extension NSImage {
    /// The app icon at `size` points, scaled down from its 1024 px rendition.
    ///
    /// The asset catalog's pre-rendered small sizes, and the system's own small
    /// renderings, alias the icon's thin edges, so at 60–128 pt the zipper looks
    /// pixelated. Scaling the largest rendition down with high-quality
    /// interpolation keeps it smooth. It is the default variant, as in the Dock
    /// with the default icon style; `NSApp.applicationIconImage` rendered
    /// offscreen would turn dark with the app's appearance instead.
    static func appIcon(size: CGFloat) -> NSImage {
        let large = NSImage(named: "AppIcon")?.representations
            .max { $0.pixelsWide < $1.pixelsWide }?
            .cgImage(forProposedRect: nil, context: nil, hints: nil)
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { bounds in
            guard let large, let context = NSGraphicsContext.current?.cgContext else { return false }
            context.interpolationQuality = .high
            context.draw(large, in: bounds)
            return true
        }
    }
}
