#!/usr/bin/env swift

// Rebuild the archive document icon after changing MacPacker's icon palette.
// Usage: swift scripts/generate-archive-document-icon.swift <output.icns> <scratch-directory>

import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fatalError("Expected output .icns path and scratch directory")
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let scratch = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let iconset = scratch.appendingPathComponent("ArchiveDocument.iconset", isDirectory: true)
let fm = FileManager.default
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> NSColor {
    NSColor(calibratedRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}

func render(size: Int) throws -> Data {
    let image = NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { _ in
        let page = NSBezierPath()
        page.move(to: NSPoint(x: 185, y: 120))
        page.line(to: NSPoint(x: 185, y: 895))
        page.curve(to: NSPoint(x: 220, y: 930), controlPoint1: NSPoint(x: 185, y: 916), controlPoint2: NSPoint(x: 200, y: 930))
        page.line(to: NSPoint(x: 620, y: 930))
        page.line(to: NSPoint(x: 840, y: 710))
        page.line(to: NSPoint(x: 840, y: 120))
        page.curve(to: NSPoint(x: 805, y: 85), controlPoint1: NSPoint(x: 840, y: 100), controlPoint2: NSPoint(x: 825, y: 85))
        page.line(to: NSPoint(x: 220, y: 85))
        page.curve(to: NSPoint(x: 185, y: 120), controlPoint1: NSPoint(x: 200, y: 85), controlPoint2: NSPoint(x: 185, y: 100))
        page.close()
        NSColor.white.setFill()
        page.fill()
        color(0xC9CBD0).setStroke()
        page.lineWidth = 14
        page.stroke()

        let fold = NSBezierPath()
        fold.move(to: NSPoint(x: 620, y: 930))
        fold.line(to: NSPoint(x: 620, y: 740))
        fold.curve(to: NSPoint(x: 650, y: 710), controlPoint1: NSPoint(x: 620, y: 722), controlPoint2: NSPoint(x: 632, y: 710))
        fold.line(to: NSPoint(x: 840, y: 710))
        fold.close()
        color(0xE9EAED).setFill()
        fold.fill()
        color(0xC9CBD0).setStroke()
        fold.stroke()

        let badge = NSBezierPath(roundedRect: NSRect(x: 260, y: 205, width: 505, height: 500), xRadius: 90, yRadius: 90)
        color(0xFE910E).setFill()
        badge.fill()
        NSGraphicsContext.saveGraphicsState()
        badge.addClip()
        color(0xFC6229).setFill()
        NSRect(x: 260, y: 205, width: 252, height: 500).fill()
        NSGraphicsContext.restoreGraphicsState()

        let zipper = NSBezierPath()
        zipper.move(to: NSPoint(x: 420, y: 700))
        zipper.line(to: NSPoint(x: 488, y: 555))
        zipper.line(to: NSPoint(x: 488, y: 355))
        zipper.line(to: NSPoint(x: 536, y: 355))
        zipper.line(to: NSPoint(x: 536, y: 555))
        zipper.line(to: NSPoint(x: 604, y: 700))
        zipper.lineWidth = 26
        color(0x343537).setStroke()
        zipper.stroke()
        for row in 0..<6 {
            let y = CGFloat(610 - row * 39)
            color(0x343537).setFill()
            NSBezierPath(roundedRect: NSRect(x: 439, y: y, width: 60, height: 22), xRadius: 4, yRadius: 4).fill()
            NSBezierPath(roundedRect: NSRect(x: 525, y: y, width: 60, height: 22), xRadius: 4, yRadius: 4).fill()
        }
        let pull = NSBezierPath(roundedRect: NSRect(x: 464, y: 255, width: 96, height: 120), xRadius: 28, yRadius: 28)
        color(0x343537).setFill()
        pull.fill()
        return true
    }
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let resized = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                         bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: resized) else { fatalError("Could not render icon") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    bitmap.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = resized.representation(using: .png, properties: [:]) else { fatalError("Could not encode icon") }
    return png
}

for (name, pixels) in [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
] {
    try render(size: pixels).write(to: iconset.appendingPathComponent(name))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
