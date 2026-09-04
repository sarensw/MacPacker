//
//  WindowFramePlacementTests.swift
//  Modules
//
//  Created by Stephan Arenswald on 31.08.26.
//

import Testing
import Foundation
@testable import Core

extension AllCoreTests {

    struct WindowFramePlacementTests {

        /// A single 1920×1080 display with the menu bar taken off the top.
        private let laptop = CGRect(x: 0, y: 0, width: 1920, height: 1055)
        /// A second display sitting to the right of it.
        private let external = CGRect(x: 1920, y: 0, width: 2560, height: 1415)

        @Test func frameFullyOnScreenIsUsable() {
            let frame = CGRect(x: 200, y: 200, width: 800, height: 500)
            #expect(WindowFramePlacement.isUsable(frame, on: [laptop]))
        }

        @Test func frameOnADisconnectedDisplayIsNotUsable() {
            // saved on the external display, which is now unplugged
            let frame = CGRect(x: 2400, y: 300, width: 800, height: 500)
            #expect(!WindowFramePlacement.isUsable(frame, on: [laptop]))
        }

        @Test func frameOnASecondDisplayIsUsable() {
            let frame = CGRect(x: 2400, y: 300, width: 800, height: 500)
            #expect(WindowFramePlacement.isUsable(frame, on: [laptop, external]))
        }

        /// The regression that made the plain `intersects` check wrong: a few
        /// pixels of the window poke onto the screen and everything else is off.
        @Test func sliverOfOverlapIsNotUsable() {
            let frame = CGRect(x: 1910, y: 300, width: 800, height: 500)
            #expect(!WindowFramePlacement.isUsable(frame, on: [laptop]))
        }

        /// A big window only has to show 300×200 — half of it would be a
        /// stricter bar than the user needs to grab it.
        @Test func largeWindowNeedsOnlyTheCappedMinimum() {
            let frame = CGRect(x: 1600, y: 800, width: 2000, height: 1200)
            let overlap = laptop.intersection(frame)
            #expect(overlap.width == 320 && overlap.height == 255)
            #expect(WindowFramePlacement.isUsable(frame, on: [laptop]))
        }

        /// A small window is measured against half of itself, not against 300×200.
        @Test func smallWindowIsMeasuredAgainstHalfOfItself() {
            let frame = CGRect(x: 1800, y: 300, width: 200, height: 150)
            #expect(WindowFramePlacement.isUsable(frame, on: [laptop]))

            let mostlyOff = CGRect(x: 1880, y: 300, width: 200, height: 150)
            #expect(!WindowFramePlacement.isUsable(mostlyOff, on: [laptop]))
        }

        @Test func emptyFrameIsNotUsable() {
            #expect(!WindowFramePlacement.isUsable(.zero, on: [laptop]))
        }

        @Test func noScreensAtAllIsNotUsable() {
            let frame = CGRect(x: 200, y: 200, width: 800, height: 500)
            #expect(!WindowFramePlacement.isUsable(frame, on: []))
        }
    }
}
