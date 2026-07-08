import Foundation
import Observation
@testable import Loadable

// MARK: - Errors

/// A distinguishable test error so assertions can verify *which* failure
/// landed in `phase` (e.g. the last error of a retry sequence).
enum LoadError: Error, Sendable, Equatable, Hashable {
    case code(Int)
    case cancelledUpstream
}

// MARK: - Thread-safe boxes

/// A lock-guarded counter that `@Sendable` operations can capture to record
/// how many times they were invoked.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0

    var value: Int {
        lock.withLock { _value }
    }

    /// Increments and returns the new value.
    @discardableResult
    func increment() -> Int {
        lock.withLock {
            _value += 1
            return _value
        }
    }
}

/// A lock-guarded flag that `@Sendable` operations can capture to record
/// that something happened (e.g. the operation observed cancellation).
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var _isSet = false

    var isSet: Bool {
        lock.withLock { _isSet }
    }

    func set() {
        lock.withLock { _isSet = true }
    }
}

// MARK: - Gate

/// A one-shot suspension point that ignores task cancellation, so tests can
/// deterministically control *when* an operation completes — including after
/// the task running it has been cancelled.
final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: UnsafeContinuation<Void, Never>?
    private var isOpen = false

    /// Suspends until ``open()`` is called. Returns immediately if the gate
    /// is already open. Does not resume early on task cancellation.
    func wait() async {
        await withUnsafeContinuation { (c: UnsafeContinuation<Void, Never>) in
            lock.lock()
            if isOpen {
                lock.unlock()
                c.resume()
            } else {
                continuation = c
                lock.unlock()
            }
        }
    }

    /// Opens the gate, resuming a waiter if one is suspended.
    func open() {
        lock.lock()
        isOpen = true
        let waiter = continuation
        continuation = nil
        lock.unlock()
        waiter?.resume()
    }
}

// MARK: - Test clocks

/// The instant type shared by the test clocks below.
struct TestInstant: InstantProtocol {
    var offset: Duration = .zero

    func advanced(by duration: Duration) -> TestInstant {
        TestInstant(offset: offset + duration)
    }

    func duration(to other: TestInstant) -> Duration {
        other.offset - offset
    }

    static func < (lhs: TestInstant, rhs: TestInstant) -> Bool {
        lhs.offset < rhs.offset
    }
}

/// A clock whose `sleep` returns immediately while recording every requested
/// duration, so backoff sequences can be asserted without real sleeping.
final class RecordingClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var _sleeps: [Duration] = []

    var now: TestInstant { TestInstant() }
    var minimumResolution: Duration { .zero }

    /// Every duration passed to `sleep`, in order.
    var sleeps: [Duration] {
        lock.withLock { _sleeps }
    }

    func sleep(until deadline: TestInstant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        lock.withLock { _sleeps.append(TestInstant().duration(to: deadline)) }
    }
}

/// A clock whose `sleep` suspends forever, resuming only when the task is
/// cancelled — for deterministically testing cancellation during a backoff
/// sleep. ``sleepStarted`` opens as soon as a sleeper suspends.
final class HangingClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: UnsafeContinuation<Void, any Error>] = [:]

    /// Opens when the first `sleep` call has suspended.
    let sleepStarted = Gate()

    var now: TestInstant { TestInstant() }
    var minimumResolution: Duration { .zero }

    func sleep(until deadline: TestInstant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withUnsafeThrowingContinuation { (c: UnsafeContinuation<Void, any Error>) in
                lock.lock()
                continuations[id] = c
                lock.unlock()
                sleepStarted.open()
            }
        } onCancel: {
            lock.lock()
            let waiter = continuations.removeValue(forKey: id)
            lock.unlock()
            waiter?.resume(throwing: CancellationError())
        }
    }
}

// MARK: - Phase observation

/// Records every `phase` transition of a `LoadableState<String, LoadError>`
/// via `withObservationTracking`, synchronously at each mutation, so tests
/// can prove which phases were (and were not) set.
///
/// `onChange` fires at `willSet`, so ``observedPhases`` holds the value each
/// transition moved *away from*; read `state.phase` for the final value.
@MainActor
final class PhaseObserver {
    private let state: LoadableState<String, LoadError>

    /// The phase values observed at each change, in order (pre-change values).
    private(set) var observedPhases: [LoadableState<String, LoadError>.Phase] = []

    init(observing state: LoadableState<String, LoadError>) {
        self.state = state
        track()
    }

    private func track() {
        withObservationTracking {
            _ = state.phase
        } onChange: { [weak self] in
            // Phase mutations only happen from @MainActor methods, so
            // willSet observation fires synchronously on the main actor.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.observedPhases.append(self.state.phase)
                self.track()
            }
        }
    }
}
