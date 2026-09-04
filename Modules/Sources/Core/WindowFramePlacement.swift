//
//  WindowFramePlacement.swift
//  Modules
//
//  Created by Stephan Arenswald on 31.08.26.
//

import Foundation

/// Geometry for restoring a remembered window frame. Pure math so it is testable
/// without a screen; the app passes its `NSScreen.visibleFrame`s in.
public enum WindowFramePlacement {

    /// Whether a remembered frame is still worth restoring. A frame saved on a
    /// display that is gone lands off-screen, which looks like a window that never
    /// opened, and a sliver is no better than none. Require half the window visible,
    /// or 300×200 for a large one, whichever is smaller.
    public static func isUsable(_ frame: CGRect, on visibleFrames: [CGRect]) -> Bool {
        guard !frame.isEmpty else { return false }
        let minWidth = min(frame.width * 0.5, 300)
        let minHeight = min(frame.height * 0.5, 200)
        return visibleFrames.contains { visible in
            // a disjoint intersection is CGRect.null: zero size, fails both checks
            let overlap = visible.intersection(frame)
            return overlap.width >= minWidth && overlap.height >= minHeight
        }
    }
}
