//
//  MainRunLoopTests.swift
//  Modules
//
//  Reaching the main thread while a job on the main queue waits in a run
//  loop nested in it, as quitting from a Task on the main actor does (#413).
//

import CoreFoundation
import Foundation
import Testing
@testable import Core

extension AllCoreTests {

    @MainActor
    struct MainRunLoopTests {

        @MainActor
        final class Flag {
            var isSet = false
        }

        /// `terminate(_:)` called from a Task on the main actor waits in a
        /// modal run loop, inside that Task's job, for the cache to be
        /// cleared. The reply to it has to get through to the main thread
        /// there; one sent as a Task on the main actor never ran.
        @Test func reachesTheMainThreadWhileAMainQueueJobWaitsInANestedLoop() {
            let answered = Flag()
            Task.detached {
                MainRunLoop.perform { answered.isSet = true }
            }
            let modalPanel = CFRunLoopMode("NSModalPanelRunLoopMode" as CFString)
            let deadline = Date.now.addingTimeInterval(2)
            while !answered.isSet, Date.now < deadline {
                _ = CFRunLoopRunInMode(modalPanel, 0.05, true)
            }
            #expect(answered.isSet)
        }

        @Test func runsInTheDefaultMode() {
            let ran = Flag()
            MainRunLoop.perform { ran.isSet = true }
            let deadline = Date.now.addingTimeInterval(2)
            while !ran.isSet, Date.now < deadline {
                _ = CFRunLoopRunInMode(.defaultMode, 0.05, true)
            }
            #expect(ran.isSet)
        }
    }
}
