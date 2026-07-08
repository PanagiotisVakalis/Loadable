import Testing
import Observation
@testable import Loadable

@MainActor
struct CancellationTests {

    // MARK: - cancel()

    @Test func cancelRevertsPhaseAndOperationObservesCancellation() async {
        let state = LoadableState<String, LoadError>()
        let gate = Gate()
        let sawCancellation = Flag()

        // Seed a stable value so the revert target is observable.
        await state.run { "initial" }
        #expect(state.phase == .success("initial"))

        let task = state.load { @Sendable () throws(LoadError) -> String in
            await gate.wait()
            if Task.isCancelled {
                sawCancellation.set()
                throw .cancelledUpstream
            }
            return "refreshed"
        }

        #expect(state.phase == .loading)
        state.cancel()

        // D2: phase reverts to the pre-.loading value, stale data stays visible.
        #expect(state.phase == .success("initial"))

        gate.open()
        await task.value

        // The operation observed cancellation, and its late failure did not
        // overwrite the reverted phase.
        #expect(sawCancellation.isSet)
        #expect(state.phase == .success("initial"))
    }

    @Test func cancelRevertsToIdleWhenNothingWasLoadedBefore() async {
        let state = LoadableState<String, LoadError>()
        let gate = Gate()

        let task = state.load { @Sendable () throws(LoadError) -> String in
            await gate.wait()
            return "value"
        }

        state.cancel()
        #expect(state.phase == .idle)

        gate.open()
        await task.value
        #expect(state.phase == .idle)
    }

    @Test func cancelWithNoInFlightTaskIsANoOp() async {
        let state = LoadableState<String, LoadError>()

        state.cancel()
        #expect(state.phase == .idle)

        // Also a no-op after a load has already finished.
        await state.load { "done" }.value
        state.cancel()
        #expect(state.phase == .success("done"))
    }

    // MARK: - Latest wins / out-of-order guard

    @Test func rapidLoadsCancelPreviousAndLastResultWins() async {
        let state = LoadableState<String, LoadError>()
        let firstGate = Gate()
        let secondGate = Gate()

        let first = state.load { @Sendable () throws(LoadError) -> String in
            await firstGate.wait()
            return "first"
        }
        let second = state.load { @Sendable () throws(LoadError) -> String in
            await secondGate.wait()
            return "second"
        }

        #expect(first.isCancelled)
        #expect(!second.isCancelled)

        // Let the *second* operation finish first…
        secondGate.open()
        await second.value
        #expect(state.phase == .success("second"))

        // …then let the first (cancelled) operation complete out of order.
        firstGate.open()
        await first.value

        // The stale completion must not overwrite the newer result.
        #expect(state.phase == .success("second"))
    }

    @Test func staleFailureDoesNotOverwriteNewerResult() async {
        let state = LoadableState<String, LoadError>()
        let firstGate = Gate()

        let first = state.load { @Sendable () throws(LoadError) -> String in
            await firstGate.wait()
            throw .code(1)
        }
        let second = state.load { "second" }

        await second.value
        #expect(state.phase == .success("second"))

        firstGate.open()
        await first.value
        #expect(state.phase == .success("second"))
    }

    // MARK: - Cancellation during retry backoff

    @Test func cancelDuringBackoffSleepStopsRetrying() async {
        let state = LoadableState<String, LoadError>()
        let clock = HangingClock()
        let invocations = Counter()

        let task = state.load(
            retry: RetryPolicy(maxAttempts: 3, backoff: .fixed(.seconds(1))),
            clock: clock
        ) { @Sendable () throws(LoadError) -> String in
            invocations.increment()
            throw .code(1)
        }

        // Wait until the first attempt has failed and the backoff sleep has
        // actually suspended, then cancel.
        await clock.sleepStarted.wait()
        state.cancel()
        await task.value

        // The sequence ended immediately: no second attempt, no .failure.
        #expect(invocations.value == 1)
        #expect(state.phase == .idle)
    }

    @Test func cancellingReturnedTaskDuringBackoffAlsoStopsAndRevertsPhase() async {
        let state = LoadableState<String, LoadError>()
        let clock = HangingClock()
        let invocations = Counter()

        await state.run { "initial" }

        let task = state.load(
            retry: RetryPolicy(maxAttempts: 3, backoff: .fixed(.seconds(1))),
            clock: clock
        ) { @Sendable () throws(LoadError) -> String in
            invocations.increment()
            throw .code(1)
        }

        await clock.sleepStarted.wait()
        task.cancel()
        await task.value

        #expect(invocations.value == 1)
        #expect(state.phase == .success("initial"))
    }

    // MARK: - Task ownership

    @Test func loadReturnsAwaitableTask() async {
        let state = LoadableState<String, LoadError>()

        let task = state.load { "value" }
        await task.value

        #expect(state.phase == .success("value"))
    }

    @Test func loadReportsFailureWhenNotCancelled() async {
        let state = LoadableState<String, LoadError>()

        await state.load { @Sendable () throws(LoadError) -> String in
            throw .code(7)
        }.value

        #expect(state.phase == .failure(.code(7)))
    }

    @Test func loadAndCancelDoNotDisturbPhaseObservationBeyondExpectedTransitions() async {
        let state = LoadableState<String, LoadError>()
        let observer = PhaseObserver(observing: state)
        let gate = Gate()

        let task = state.load { @Sendable () throws(LoadError) -> String in
            await gate.wait()
            return "value"
        }
        state.cancel()
        gate.open()
        await task.value

        // .idle → .loading → (revert to) .idle, and nothing afterwards.
        #expect(observer.observedPhases == [.idle, .loading])
        #expect(state.phase == .idle)
    }
}
