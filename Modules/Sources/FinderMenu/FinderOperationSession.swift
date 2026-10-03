import Foundation

/// Tracks a process launched only to do Finder work. Requests include folder
/// and password prompts, archive loading, and whole multi-file batches — not
/// just the intervals in which the progress center has an active job.
public struct FinderOperationSession {
    public static let launchArgument = "FinderProgressOnly"
    public private(set) var isTransient: Bool
    private var requests: Set<UUID> = []
    private var hasReceivedRequest = false

    public init(isTransient: Bool = false) {
        self.isTransient = isTransient
    }

    public mutating func begin() -> UUID {
        let id = UUID()
        requests.insert(id)
        hasReceivedRequest = true
        return id
    }

    public mutating func finish(_ id: UUID) {
        requests.remove(id)
    }

    /// Opening the app or an archive explicitly converts it to a normal session.
    public mutating func keepRunning() {
        isTransient = false
    }

    /// A bounded launch timer may reveal the app only if no URL ever arrived.
    public var needsLaunchFallback: Bool { isTransient && !hasReceivedRequest }

    public var hasPendingRequests: Bool { !requests.isEmpty }

    public func shouldTerminate(hasProgress: Bool, hasWindows: Bool) -> Bool {
        isTransient && hasReceivedRequest && requests.isEmpty && !hasProgress && !hasWindows
    }
}
