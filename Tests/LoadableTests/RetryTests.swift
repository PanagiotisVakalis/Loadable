import Testing
import Observation
@testable import Loadable

@MainActor
struct RetryTests {

    // MARK: - run(retry:) outcomes

    @Test func succeedsAfterTransientFailures() async {
        let state = LoadableState<String, LoadError>()
        let clock = RecordingClock()
        let invocations = Counter()

        await state.run(retry: RetryPolicy(maxAttempts: 3), clock: clock) {
            @Sendable () throws(LoadError) -> String in
            let attempt = invocations.increment()
            if attempt < 3 { throw .code(attempt) }
            return "recovered"
        }

        #expect(invocations.value == 3)
        if case .success(let value) = state.phase {
            #expect(value == "recovered")
        } else {
            Issue.record("Expected .success after retries")
        }
    }

    @Test func failsWithLastErrorAfterExhaustingAttempts() async {
        let state = LoadableState<String, LoadError>()
        let clock = RecordingClock()
        let invocations = Counter()

        await state.run(retry: RetryPolicy(maxAttempts: 3), clock: clock) {
            @Sendable () throws(LoadError) -> String in
            throw .code(invocations.increment())
        }

        #expect(invocations.value == 3)
        if case .failure(let error) = state.phase {
            #expect(error == .code(3))
        } else {
            Issue.record("Expected .failure after exhausting attempts")
        }
    }

    @Test func shouldRetryFalseStopsAfterFirstAttempt() async {
        let state = LoadableState<String, LoadError>()
        let clock = RecordingClock()
        let invocations = Counter()

        await state.run(
            retry: RetryPolicy(maxAttempts: 3),
            shouldRetry: { $0 != .code(1) },
            clock: clock
        ) { @Sendable () throws(LoadError) -> String in
            throw .code(invocations.increment())
        }

        #expect(invocations.value == 1)
        #expect(clock.sleeps.isEmpty)
        if case .failure(let error) = state.phase {
            #expect(error == .code(1))
        } else {
            Issue.record("Expected .failure without retries")
        }
    }

    // MARK: - Backoff delays

    @Test func exponentialBackoffSleepsExpectedDelays() async {
        let state = LoadableState<String, LoadError>()
        let clock = RecordingClock()

        await state.run(
            retry: RetryPolicy(
                maxAttempts: 5,
                backoff: .exponential(initial: .seconds(1), multiplier: 2, max: .seconds(4))
            ),
            clock: clock
        ) { @Sendable () throws(LoadError) -> String in
            throw .code(0)
        }

        #expect(clock.sleeps == [.seconds(1), .seconds(2), .seconds(4), .seconds(4)])
    }

    @Test func fixedBackoffSleepsConstantDelays() async {
        let state = LoadableState<String, LoadError>()
        let clock = RecordingClock()

        await state.run(
            retry: .fixed(maxAttempts: 3, delay: .milliseconds(250)),
            clock: clock
        ) { @Sendable () throws(LoadError) -> String in
            throw .code(0)
        }

        #expect(clock.sleeps == [.milliseconds(250), .milliseconds(250)])
    }

    // MARK: - .never parity with v1

    @Test func neverPolicyMatchesV1SuccessBehaviour() async {
        let v1 = LoadableState<String, LoadError>()
        let v2 = LoadableState<String, LoadError>()
        let clock = RecordingClock()

        await v1.run { "hello" }
        await v2.run(retry: .never, clock: clock) { "hello" }

        #expect(v1.phase == v2.phase)
        #expect(clock.sleeps.isEmpty)
    }

    @Test func neverPolicyMatchesV1FailureBehaviour() async {
        let v1 = LoadableState<String, LoadError>()
        let v2 = LoadableState<String, LoadError>()
        let clock = RecordingClock()
        let invocations = Counter()

        await v1.run { @Sendable () throws(LoadError) -> String in throw .code(1) }
        await v2.run(retry: .never, clock: clock) { @Sendable () throws(LoadError) -> String in
            invocations.increment()
            throw .code(1)
        }

        #expect(v1.phase == v2.phase)
        #expect(invocations.value == 1)
        #expect(clock.sleeps.isEmpty)
    }

    // MARK: - Phase transitions

    @Test func phaseIsNeverFailureBetweenAttempts() async {
        let state = LoadableState<String, LoadError>()
        let observer = PhaseObserver(observing: state)
        let clock = RecordingClock()
        let invocations = Counter()

        await state.run(retry: RetryPolicy(maxAttempts: 3), clock: clock) {
            @Sendable () throws(LoadError) -> String in
            let attempt = invocations.increment()
            if attempt < 3 { throw .code(attempt) }
            return "recovered"
        }

        // Exactly two transitions: .idle → .loading → .success. A flicker to
        // .failure between attempts would record extra pre-change values.
        #expect(observer.observedPhases == [.idle, .loading])
        #expect(state.phase == .success("recovered"))
    }

    @Test func phaseStaysLoadingUntilTerminalFailure() async {
        let state = LoadableState<String, LoadError>()
        let observer = PhaseObserver(observing: state)
        let clock = RecordingClock()

        await state.run(retry: RetryPolicy(maxAttempts: 3), clock: clock) {
            @Sendable () throws(LoadError) -> String in
            throw .code(9)
        }

        #expect(observer.observedPhases == [.idle, .loading])
        #expect(state.phase == .failure(.code(9)))
    }
}
