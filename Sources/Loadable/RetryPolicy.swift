/// A value describing how many times a failed operation should be attempted
/// and how long to wait between attempts.
///
/// Pass a policy to ``LoadableState/run(retry:shouldRetry:clock:_:)`` or
/// ``LoadableState/load(retry:shouldRetry:clock:_:)`` to retry transient
/// failures without writing loops or sleep logic in your view model:
///
/// ```swift
/// // 3 attempts total, waiting 1s then 2s between them.
/// await state.run(retry: .exponential(maxAttempts: 3)) {
///     try await api.fetchUser()
/// }
/// ```
public struct RetryPolicy: Sendable, Equatable, Hashable {

    /// The strategy used to compute the delay before each retry.
    public enum Backoff: Sendable, Equatable, Hashable {
        /// Retry immediately, with no delay between attempts.
        case none
        /// Wait the same fixed duration before every retry.
        case fixed(Duration)
        /// Wait `initial` before the first retry, multiplying the delay by
        /// `multiplier` for each subsequent retry, never exceeding `max`.
        ///
        /// For example, `.exponential(initial: .seconds(1), multiplier: 2, max: .seconds(4))`
        /// produces delays of 1s, 2s, 4s, 4s…
        case exponential(initial: Duration, multiplier: Double, max: Duration)
    }

    /// The total number of attempts, including the first one.
    ///
    /// A value of 3 means 1 initial attempt plus up to 2 retries. Values
    /// below 1 are clamped to 1.
    public var maxAttempts: Int

    /// The backoff strategy applied between attempts.
    public var backoff: Backoff

    /// Whether to apply full jitter to each computed delay.
    ///
    /// When `true`, the actual delay is a uniformly random duration between
    /// zero and the computed delay, which avoids thundering-herd retries when
    /// many clients fail at the same moment. Off by default.
    public var jitter: Bool

    /// Creates a retry policy.
    ///
    /// - Parameters:
    ///   - maxAttempts: Total attempts including the first (clamped to at least 1).
    ///   - backoff: The delay strategy between attempts. Defaults to `.none`.
    ///   - jitter: Whether to apply full jitter to each delay. Defaults to `false`.
    public init(maxAttempts: Int, backoff: Backoff = .none, jitter: Bool = false) {
        self.maxAttempts = Swift.max(1, maxAttempts)
        self.backoff = backoff
        self.jitter = jitter
    }

    /// A policy that never retries — a single attempt, equivalent to v1
    /// ``LoadableState/run(_:)`` behaviour. This is the default.
    public static let never = RetryPolicy(maxAttempts: 1)

    /// An exponential-backoff policy with sensible defaults.
    ///
    /// ```swift
    /// // 1s, 2s, 4s… between attempts, capped at 30s.
    /// let policy = RetryPolicy.exponential(maxAttempts: 5)
    /// ```
    ///
    /// - Parameters:
    ///   - maxAttempts: Total attempts including the first. Defaults to 3.
    ///   - initial: The delay before the first retry. Defaults to 1 second.
    ///   - multiplier: The factor applied to the delay after each retry. Defaults to 2.
    ///   - max: The upper bound on any single delay. Defaults to 30 seconds.
    ///   - jitter: Whether to apply full jitter to each delay. Defaults to `false`.
    public static func exponential(
        maxAttempts: Int = 3,
        initial: Duration = .seconds(1),
        multiplier: Double = 2,
        max: Duration = .seconds(30),
        jitter: Bool = false
    ) -> RetryPolicy {
        RetryPolicy(
            maxAttempts: maxAttempts,
            backoff: .exponential(initial: initial, multiplier: multiplier, max: max),
            jitter: jitter
        )
    }

    /// A fixed-delay policy: the same pause before every retry.
    ///
    /// - Parameters:
    ///   - maxAttempts: Total attempts including the first.
    ///   - delay: The pause before each retry.
    ///   - jitter: Whether to apply full jitter to each delay. Defaults to `false`.
    public static func fixed(
        maxAttempts: Int,
        delay: Duration,
        jitter: Bool = false
    ) -> RetryPolicy {
        RetryPolicy(maxAttempts: maxAttempts, backoff: .fixed(delay), jitter: jitter)
    }

    /// The delay to wait after the given failed attempt, before the next one.
    ///
    /// - Parameter attempt: The 1-based attempt number that just failed.
    func delay(afterAttempt attempt: Int) -> Duration {
        var generator = SystemRandomNumberGenerator()
        return delay(afterAttempt: attempt, using: &generator)
    }

    /// Testable variant of ``delay(afterAttempt:)`` with an injectable
    /// random number generator for deterministic jitter.
    func delay(
        afterAttempt attempt: Int,
        using generator: inout some RandomNumberGenerator
    ) -> Duration {
        let base: Duration
        switch backoff {
        case .none:
            base = .zero
        case .fixed(let duration):
            base = duration
        case .exponential(let initial, let multiplier, let maxDelay):
            let cap = maxDelay.secondsValue
            var seconds = Swift.min(initial.secondsValue, cap)
            for _ in 1..<Swift.max(1, attempt) {
                seconds = Swift.min(seconds * multiplier, cap)
            }
            base = .seconds(seconds)
        }
        guard jitter, base > .zero else { return base }
        return .seconds(Double.random(in: 0...base.secondsValue, using: &generator))
    }
}

extension Duration {
    /// The duration expressed as a floating-point number of seconds.
    var secondsValue: Double {
        Double(components.seconds) + Double(components.attoseconds) * 1e-18
    }
}
