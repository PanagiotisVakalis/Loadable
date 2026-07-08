import Observation

/// An observable container that drives a four-state async loading machine.
///
/// Declare one property per async resource in your `@Observable` view model,
/// then call ``run(_:)`` to load it. SwiftUI views switch over ``phase`` to
/// render each state without boilerplate.
///
/// ```swift
/// @Observable
/// class UserViewModel {
///     var user = LoadableState<User, Error>()
///
///     func load() async {
///         await user.run { try await api.fetchUser() }
///     }
/// }
///
/// // In the view:
/// switch vm.user.phase {
/// case .idle:    Text("Tap to load")
/// case .loading: ProgressView()
/// case .success(let user): Text(user.name)
/// case .failure(let error): Text(error.localizedDescription)
/// }
/// ```
@Observable
public final class LoadableState<Value: Sendable, Failure: Error & Sendable> {

    /// The four states an async operation can be in.
    public enum Phase: Sendable {
        case idle
        case loading
        case success(Value)
        case failure(Failure)
    }

    /// The current phase of the loading operation.
    public private(set) var phase: Phase = .idle

    /// The task backing the in-flight managed load, if any.
    @ObservationIgnored
    private var activeTask: Task<Void, Never>?

    /// Monotonically increasing token identifying the current managed load.
    /// A completed task only writes ``phase`` if its generation still
    /// matches, which guards against out-of-order completion.
    @ObservationIgnored
    private var generation = 0

    /// The last stable phase before a managed load set `.loading`, restored
    /// when that load is cancelled.
    @ObservationIgnored
    private var phaseBeforeLoading: Phase = .idle

    public init() {}

    deinit {
        activeTask?.cancel()
    }

    /// Runs `operation`, updating ``phase`` to `.loading` immediately, then
    /// to `.success` or `.failure` depending on the outcome.
    ///
    /// - Parameter operation: The async throwing work to perform. Use typed
    ///   throws (`throws(Failure)`) at the call site when the error type is
    ///   known at compile time.
    @MainActor
    public func run(_ operation: @Sendable () async throws(Failure) -> Value) async {
        phase = .loading
        do {
            phase = try await .success(operation())
        } catch {
            phase = .failure(error)
        }
    }

    /// Runs `operation`, retrying failed attempts according to `policy`.
    ///
    /// ``phase`` becomes `.loading` immediately and stays `.loading` for the
    /// entire retry sequence — it never flickers to `.failure` between
    /// attempts. It ends `.success` on the first successful attempt, or
    /// `.failure` with the last error once attempts are exhausted or
    /// `shouldRetry` declines to continue.
    ///
    /// ```swift
    /// @Observable
    /// class UserViewModel {
    ///     var user = LoadableState<User, APIError>()
    ///
    ///     func load() async {
    ///         await user.run(retry: .exponential(maxAttempts: 3)) {
    ///             try await api.fetchUser()
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// If the surrounding task is cancelled during a backoff sleep, the retry
    /// sequence aborts immediately and ``phase`` reverts to the value it held
    /// before `.loading`.
    ///
    /// - Parameters:
    ///   - policy: How many attempts to make and how long to wait between
    ///     them. ``RetryPolicy/never`` behaves exactly like ``run(_:)``.
    ///   - shouldRetry: Decides whether a thrown error is worth retrying.
    ///     Return `false` for non-transient errors (e.g. authentication
    ///     failures) to fail fast. Defaults to retrying every error.
    ///   - clock: The clock used for backoff sleeps. Defaults to
    ///     `ContinuousClock()`; inject a test clock to make view-model tests
    ///     instant and deterministic.
    ///   - operation: The async throwing work to perform. Use typed throws
    ///     (`throws(Failure)`) at the call site when the error type is known
    ///     at compile time.
    @MainActor
    public func run(
        retry policy: RetryPolicy,
        shouldRetry: @Sendable (Failure) -> Bool = { _ in true },
        clock: any Clock<Duration> = ContinuousClock(),
        _ operation: @Sendable () async throws(Failure) -> Value
    ) async {
        let previousPhase = phase
        phase = .loading
        switch await Self.attempt(policy: policy, shouldRetry: shouldRetry, clock: clock, operation: operation) {
        case .success(let value):
            phase = .success(value)
        case .failure(let error):
            phase = .failure(error)
        case .cancelled:
            phase = previousPhase
        }
    }

    /// Starts `operation` in a task owned by this state, cancelling any
    /// load already in flight (latest wins).
    ///
    /// Unlike ``run(_:)``, callers don't need to hold a `Task` — this is the
    /// fire-and-forget style suited to `Button` actions, `onAppear`, and
    /// `.task {}`:
    ///
    /// ```swift
    /// Button("Refresh") {
    ///     viewModel.user.load(retry: .exponential(maxAttempts: 3)) {
    ///         try await api.fetchUser()
    ///     }
    /// }
    /// Button("Cancel") {
    ///     viewModel.user.cancel()
    /// }
    /// ```
    ///
    /// The operation runs with cooperative cancellation: ``cancel()``, a
    /// newer `load`, or deallocation of this state cancels the task, and
    /// sleeps inside the operation throw `CancellationError`. A cancelled
    /// load never writes `.failure`; ``phase`` reverts to the value it held
    /// before `.loading`, and a stale completion never overwrites the phase
    /// of a newer load. Deallocating the state cancels the in-flight task,
    /// but don't rely on that for control flow — own the lifecycle
    /// explicitly via ``cancel()`` or your view's lifetime.
    ///
    /// - Parameters:
    ///   - policy: How many attempts to make and how long to wait between
    ///     them. Defaults to ``RetryPolicy/never`` (a single attempt).
    ///   - shouldRetry: Decides whether a thrown error is worth retrying.
    ///     Defaults to retrying every error.
    ///   - clock: The clock used for backoff sleeps. Defaults to
    ///     `ContinuousClock()`; inject a test clock to make view-model tests
    ///     instant and deterministic.
    ///   - operation: The async throwing work to perform. Use typed throws
    ///     (`throws(Failure)`) at the call site when the error type is known
    ///     at compile time.
    /// - Returns: The task driving the load, discardable — await its `value`
    ///   in tests to deterministically wait for completion.
    @MainActor
    @discardableResult
    public func load(
        retry policy: RetryPolicy = .never,
        shouldRetry: @escaping @Sendable (Failure) -> Bool = { _ in true },
        clock: any Clock<Duration> = ContinuousClock(),
        _ operation: @escaping @Sendable () async throws(Failure) -> Value
    ) -> Task<Void, Never> {
        activeTask?.cancel()
        generation += 1
        let current = generation
        if case .loading = phase {} else {
            phaseBeforeLoading = phase
        }
        phase = .loading
        let task = Task { @MainActor [weak self] in
            let outcome = await Self.attempt(
                policy: policy,
                shouldRetry: shouldRetry,
                clock: clock,
                operation: operation
            )
            guard let self, self.generation == current else { return }
            self.activeTask = nil
            switch outcome {
            case .success(let value) where !Task.isCancelled:
                self.phase = .success(value)
            case .failure(let error) where !Task.isCancelled:
                self.phase = .failure(error)
            default:
                // Cancelled (during an attempt or a backoff sleep): revert
                // instead of surfacing a failure the caller asked to abandon.
                self.phase = self.phaseBeforeLoading
            }
        }
        activeTask = task
        return task
    }

    /// Cancels the in-flight managed load, if any.
    ///
    /// The running operation observes cooperative cancellation, and ``phase``
    /// immediately reverts to the value it held before `.loading` — so stale
    /// data stays visible after a cancelled refresh. Calling this with no
    /// load in flight is a safe no-op that leaves ``phase`` untouched. Loads
    /// started with ``run(_:)`` are caller-owned and unaffected.
    ///
    /// ```swift
    /// viewModel.user.cancel() // e.g. from a Cancel button or onDisappear
    /// ```
    @MainActor
    public func cancel() {
        guard let task = activeTask else { return }
        activeTask = nil
        generation += 1
        task.cancel()
        phase = phaseBeforeLoading
    }

    /// The result of a retry sequence: a terminal value, a terminal error,
    /// or an abort caused by task cancellation during a backoff sleep.
    private enum RetryOutcome {
        case success(Value)
        case failure(Failure)
        case cancelled
    }

    /// Invokes `operation` up to `policy.maxAttempts` times, sleeping on
    /// `clock` between attempts. Never touches `phase`.
    private static func attempt(
        policy: RetryPolicy,
        shouldRetry: @Sendable (Failure) -> Bool,
        clock: any Clock<Duration>,
        operation: @Sendable () async throws(Failure) -> Value
    ) async -> RetryOutcome {
        var attempt = 1
        while true {
            do throws(Failure) {
                return .success(try await operation())
            } catch {
                guard attempt < policy.maxAttempts, shouldRetry(error) else {
                    return .failure(error)
                }
                do {
                    try await clock.sleep(for: policy.delay(afterAttempt: attempt), tolerance: nil)
                } catch {
                    return .cancelled
                }
                attempt += 1
            }
        }
    }
}

extension LoadableState.Phase: Equatable where Value: Equatable, Failure: Equatable {}
extension LoadableState.Phase: Hashable where Value: Hashable, Failure: Hashable {}
