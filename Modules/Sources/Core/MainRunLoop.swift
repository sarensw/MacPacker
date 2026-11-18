//
//  MainRunLoop.swift
//  Modules
//

import CoreFoundation
import Foundation

/// The main thread, reached through its run loop instead of the main queue.
///
/// `-[NSApplication terminate:]` called from a job on the main queue, such
/// as a `Task` on the main actor, waits for
/// `reply(toApplicationShouldTerminate:)` in a run loop nested in that job.
/// The main queue runs one job at a time, so nothing queued behind it starts
/// there: no `Task` on the main actor, no `DispatchQueue.main.async`. A reply
/// sent that way never came. The app hid and stayed, and the archives opened
/// in it afterwards never loaded (#413). The run loop still runs the blocks
/// it is given, in a nested loop too.
public enum MainRunLoop {
    /// The modes the main run loop runs in: the default one, a modal
    /// session's, which the quit waits in, and a menu's or a drag's.
    static let modes: [CFRunLoopMode] = [
        .defaultMode,
        .commonModes,
        CFRunLoopMode("NSModalPanelRunLoopMode" as CFString),
        CFRunLoopMode("NSEventTrackingRunLoopMode" as CFString),
    ]

    /// Runs `body` on the main thread, in the next pass of its run loop.
    /// Callable from any thread.
    public static func perform(_ body: @escaping @MainActor @Sendable () -> Void) {
        let main = CFRunLoopGetMain()
        CFRunLoopPerformBlock(main, modes.map(\.rawValue) as CFArray) {
            MainActor.assumeIsolated(body)
        }
        CFRunLoopWakeUp(main)
    }
}
