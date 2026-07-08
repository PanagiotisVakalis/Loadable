import Testing
@testable import Loadable

struct RetryPolicyTests {

    // MARK: - Delay computation

    @Test func noneBackoffProducesZeroDelays() {
        let policy = RetryPolicy(maxAttempts: 3, backoff: .none)
        #expect(policy.delay(afterAttempt: 1) == .zero)
        #expect(policy.delay(afterAttempt: 2) == .zero)
    }

    @Test func fixedBackoffProducesConstantDelays() {
        let policy = RetryPolicy(maxAttempts: 4, backoff: .fixed(.milliseconds(500)))
        #expect(policy.delay(afterAttempt: 1) == .milliseconds(500))
        #expect(policy.delay(afterAttempt: 2) == .milliseconds(500))
        #expect(policy.delay(afterAttempt: 3) == .milliseconds(500))
    }

    @Test func exponentialBackoffDoublesAndCaps() {
        let policy = RetryPolicy(
            maxAttempts: 6,
            backoff: .exponential(initial: .seconds(1), multiplier: 2, max: .seconds(4))
        )
        #expect(policy.delay(afterAttempt: 1) == .seconds(1))
        #expect(policy.delay(afterAttempt: 2) == .seconds(2))
        #expect(policy.delay(afterAttempt: 3) == .seconds(4))
        #expect(policy.delay(afterAttempt: 4) == .seconds(4))
        #expect(policy.delay(afterAttempt: 5) == .seconds(4))
    }

    @Test func exponentialInitialDelayIsCappedByMax() {
        let policy = RetryPolicy(
            maxAttempts: 3,
            backoff: .exponential(initial: .seconds(10), multiplier: 2, max: .seconds(4))
        )
        #expect(policy.delay(afterAttempt: 1) == .seconds(4))
    }

    // MARK: - Jitter

    @Test func jitterKeepsDelayWithinComputedBound() {
        let policy = RetryPolicy(
            maxAttempts: 5,
            backoff: .exponential(initial: .seconds(1), multiplier: 2, max: .seconds(4)),
            jitter: true
        )
        var generator = SeededGenerator(seed: 42)
        for attempt in 1...4 {
            let bound = RetryPolicy(
                maxAttempts: policy.maxAttempts,
                backoff: policy.backoff
            ).delay(afterAttempt: attempt)
            let jittered = policy.delay(afterAttempt: attempt, using: &generator)
            #expect(jittered >= .zero)
            #expect(jittered <= bound)
        }
    }

    @Test func jitterIsDeterministicForSeededGenerator() {
        let policy = RetryPolicy(maxAttempts: 3, backoff: .fixed(.seconds(2)), jitter: true)
        var a = SeededGenerator(seed: 7)
        var b = SeededGenerator(seed: 7)
        #expect(policy.delay(afterAttempt: 1, using: &a) == policy.delay(afterAttempt: 1, using: &b))
    }

    @Test func jitterOffReturnsExactDelay() {
        let policy = RetryPolicy(maxAttempts: 3, backoff: .fixed(.seconds(2)))
        #expect(policy.delay(afterAttempt: 1) == .seconds(2))
    }

    // MARK: - Presets

    @Test func neverPresetIsSingleAttempt() {
        #expect(RetryPolicy.never.maxAttempts == 1)
        #expect(RetryPolicy.never.backoff == .none)
        #expect(RetryPolicy.never.jitter == false)
    }

    @Test func exponentialPresetDefaults() {
        let policy = RetryPolicy.exponential(maxAttempts: 3)
        #expect(policy.maxAttempts == 3)
        #expect(policy.backoff == .exponential(initial: .seconds(1), multiplier: 2, max: .seconds(30)))
        #expect(policy.jitter == false)
    }

    @Test func fixedPreset() {
        let policy = RetryPolicy.fixed(maxAttempts: 2, delay: .seconds(1))
        #expect(policy.maxAttempts == 2)
        #expect(policy.backoff == .fixed(.seconds(1)))
    }

    // MARK: - Validation

    @Test func maxAttemptsIsClampedToAtLeastOne() {
        #expect(RetryPolicy(maxAttempts: 0).maxAttempts == 1)
        #expect(RetryPolicy(maxAttempts: -5).maxAttempts == 1)
    }
}

/// A deterministic random number generator (SplitMix64) for jitter tests.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
