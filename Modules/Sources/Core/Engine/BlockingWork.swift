//
//  BlockingWork.swift
//  Modules
//
//  Created by Claude on 09.07.26.
//

import Foundation

/// Moves a non-Sendable value (engine handles, closures over them) across
/// the GCD hop in `runBlocking`. Safe because the owning actor serializes
/// all use — only one thread ever touches the value at a time.
private struct UnsafeTransfer<T>: @unchecked Sendable {
    let value: T
}

/// Runs a long, synchronous (blocking) operation on a GCD queue instead of
/// a Swift-concurrency cooperative thread.
///
/// The cooperative pool does not replace threads that block: a minutes-long
/// C extraction call sitting on it starves every other task in the process —
/// actors stop running, progress polling freezes, cancellation never lands.
/// GCD's global queues overcommit, so blocking there is safe.
func runBlocking<T>(_ body: @escaping () throws -> T) async throws -> T {
    let work = UnsafeTransfer(value: body)
    let boxed: UnsafeTransfer<T> = try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                continuation.resume(returning: UnsafeTransfer(value: try work.value()))
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    return boxed.value
}
