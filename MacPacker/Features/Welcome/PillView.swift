//
//  PillView.swift
//  FileFillet
//
//  Created by Stephan Arenswald on 17.05.26.
//

import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - View

public struct PillView: View {
    private let label: String
    private let background: Color
    private let foreground: Color

    /// Use a predefined style. Falls back to the style's default label.
    public init(_ style: PillStyle, label: String? = nil) {
        self.label = label ?? style.defaultLabel
        self.background = style.background
        self.foreground = style.foreground
    }

    /// Custom pill — bring your own label and colors.
    public init(label: String, background: Color, foreground: Color) {
        self.label = label
        self.background = background
        self.foreground = foreground
    }

    public var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .tracking(0.2)
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .frame(minWidth: 62)
            .background(background, in: Capsule())
    }
}

// MARK: - Style

public enum PillStyle {
    // Changelog
    case feature, fix, core, release

    public var background: Color {
        switch self {
        case .feature:     .pillFeatureBackground
        case .fix:         .pillFixBackground
        case .core:        .pillCoreBackground
        case .release:     .pillReleaseBackground
        }
    }

    public var foreground: Color {
        switch self {
        case .feature:     .pillFeatureForeground
        case .fix:         .pillFixForeground
        case .core:        .pillCoreForeground
        case .release:     .pillReleaseForeground
        }
    }

    public var defaultLabel: String {
        switch self {
        case .feature:     "Feature"
        case .fix:         "Fix"
        case .core:        "Core"
        case .release:     "Release"
        }
    }
}

// MARK: - Colors

public extension Color {
    // Changelog
    static let pillFeatureBackground = Color.adaptive(light: 0xEAF3DE, dark: 0x27500A)
    static let pillFeatureForeground = Color.adaptive(light: 0x27500A, dark: 0xC0DD97)

    static let pillFixBackground     = Color.adaptive(light: 0xE6F1FB, dark: 0x0C447C)
    static let pillFixForeground     = Color.adaptive(light: 0x0C447C, dark: 0xB5D4F4)

    static let pillCoreBackground    = Color.adaptive(light: 0xEEEDFE, dark: 0x3C3489)
    static let pillCoreForeground    = Color.adaptive(light: 0x3C3489, dark: 0xCECBF6)

    static let pillReleaseBackground = Color.adaptive(light: 0xFAECE7, dark: 0x712B13)
    static let pillReleaseForeground = Color.adaptive(light: 0x712B13, dark: 0xF5C4B3)
}

// MARK: - Adaptive Helper

private extension Color {
    /// Returns a Color that resolves to `light` (24-bit sRGB hex) in light mode
    /// and `dark` in dark mode, via the platform's dynamic color provider.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [
                .darkAqua, .vibrantDark,
                .accessibilityHighContrastDarkAqua,
                .accessibilityHighContrastVibrantDark
            ]) != nil
            return NSColor(rgb: isDark ? dark : light)
        })
        #else
        Color(uiColor: UIColor { trait in
            UIColor(rgb: trait.userInterfaceStyle == .dark ? dark : light)
        })
        #endif
    }
}

#if os(macOS)
private extension NSColor {
    convenience init(rgb hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green:   CGFloat((hex >>  8) & 0xFF) / 255.0,
            blue:    CGFloat( hex        & 0xFF) / 255.0,
            alpha:   1.0
        )
    }
}
#else
private extension UIColor {
    convenience init(rgb hex: UInt32) {
        self.init(
            red:   CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >>  8) & 0xFF) / 255.0,
            blue:  CGFloat( hex        & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
#endif

// MARK: - Previews

#Preview("Light") {
    PillPreviewGrid().preferredColorScheme(.light)
}

#Preview("Dark") {
    PillPreviewGrid().preferredColorScheme(.dark)
}

private struct PillPreviewGrid: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Changelog")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                PillView(.feature)
                PillView(.fix)
                PillView(.core)
                PillView(.release)
            }
        }
        .padding(28)
    }
}
