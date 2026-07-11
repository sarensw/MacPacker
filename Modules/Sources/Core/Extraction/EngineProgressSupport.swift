//
//  EngineProgressSupport.swift
//  Modules
//
//  Created by Claude on 09.07.26.
//

import Foundation

/// Cooperative cancellation shared with an engine's progress callback: the
/// UI sets it, the C callback polls it and aborts the extraction mid-flight
/// (something Task cancellation can't do to a blocking C call).
public final class ExtractionCancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    public func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
    }
}

/// Collects the temp directories an extraction writes into, across threads —
/// so a cancelled or failed run can hand its partial output to the regular
/// cache cleanup.
public final class ExtractionTempDirectories: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    public init() {}

    public func add(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        urls.append(url)
    }

    public var all: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }
}

/// Rate limiter for engine progress callbacks: 7-Zip reports very often;
/// forwarding every event to the main queue would flood it.
final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var lastEmission: Date?
    private let minimumInterval: TimeInterval

    init(minimumInterval: TimeInterval = 0.2) {
        self.minimumInterval = minimumInterval
    }

    /// True when enough time has passed since the last accepted emission;
    /// records `date` as the new emission time in that case.
    func shouldEmit(at date: Date) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let lastEmission, date.timeIntervalSince(lastEmission) < minimumInterval {
            return false
        }
        lastEmission = date
        return true
    }
}
