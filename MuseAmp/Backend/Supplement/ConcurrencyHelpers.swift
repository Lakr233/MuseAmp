//
//  ConcurrencyHelpers.swift
//  MuseAmp
//

import Combine
import Foundation

/// Maps each upstream value through an async closure, cancelling any in-flight
/// operation when a new value arrives. Only the result from the latest input
/// is published downstream — stale results from cancelled operations are
/// silently discarded.
///
/// Uses `map` + `switchToLatest`: each value spawns a `Task`; when a new
/// inner publisher replaces the old one, `handleEvents(receiveCancel:)`
/// cancels the previous task. On current runtimes, `Task.immediate` starts
/// the transform synchronously so zero-suspension transforms can emit before
/// a newer value arrives.
private enum AsyncMapLatestState<T: Sendable>: Sendable {
    case pending
    case ready(T)
}

extension Publisher where Failure == Never, Output: Sendable {
    func asyncMapLatest<T: Sendable>(
        _ transform: @escaping @Sendable (Output) async -> T,
    ) -> AnyPublisher<T, Never> {
        map { value -> AnyPublisher<T, Never> in
            let box = UncheckedSendableBox(CurrentValueSubject<AsyncMapLatestState<T>, Never>(.pending))
            let task: Task<Void, Never> = if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *) {
                Task.immediate {
                    let result = await transform(value)
                    guard !Task.isCancelled else { return }
                    box.value.send(.ready(result))
                }
            } else {
                Task {
                    let result = await transform(value)
                    guard !Task.isCancelled else { return }
                    box.value.send(.ready(result))
                }
            }
            return box.value
                .compactMap {
                    if case let .ready(result) = $0 {
                        return result
                    }
                    return nil
                }
                .handleEvents(receiveCancel: { task.cancel() })
                .eraseToAnyPublisher()
        }
        .switchToLatest()
        .eraseToAnyPublisher()
    }
}

/// Wraps a non-`Sendable` reference type so it can cross isolation boundaries.
///
/// The caller is responsible for ensuring the wrapped value is only accessed
/// in a thread-safe manner.
final nonisolated class UncheckedSendableBox<Value: AnyObject>: @unchecked Sendable {
    nonisolated(unsafe) let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

/// Thread-safe fire-once gate. Guarantees the closure passed to `perform(_:)`
/// executes at most once, regardless of how many threads race to call it.
final nonisolated class OnceGuard: @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var fired = false

    nonisolated func perform(_ block: () -> Void) {
        let shouldFire: Bool = lock.withLock {
            guard !fired else { return false }
            fired = true
            return true
        }
        if shouldFire {
            block()
        }
    }
}

/// Thread-safe fire-once gate for `CheckedContinuation`. Guarantees the
/// continuation is resumed exactly once, whether with a value or an error.
final nonisolated class ContinuationOnceGuard<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var didResume = false

    nonisolated func resume(
        _ continuation: CheckedContinuation<Value, any Error>,
        returning value: sending Value,
    ) {
        let shouldResume: Bool = lock.withLock {
            guard !didResume else { return false }
            didResume = true
            return true
        }
        if shouldResume {
            continuation.resume(returning: value)
        }
    }

    nonisolated func resume(
        _ continuation: CheckedContinuation<Value, any Error>,
        throwing error: any Error,
    ) {
        let shouldResume: Bool = lock.withLock {
            guard !didResume else { return false }
            didResume = true
            return true
        }
        if shouldResume {
            continuation.resume(throwing: error)
        }
    }
}
