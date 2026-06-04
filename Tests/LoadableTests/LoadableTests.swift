import Testing
import Observation
@testable import Loadable

struct LoadableTests {

    // MARK: - Pattern matching
    // These tests verify that each case of Loadable can be matched using a
    // switch statement. A `default` trap is included so any unexpected case
    // causes an explicit test failure.

    @Test func idlePatternMatch() {
        let state: Loadable<String, TestError> = .idle
        switch state {
        case .idle: break
        default: Issue.record("Expected .idle")
        }
    }

    @Test func loadingPatternMatch() {
        let state: Loadable<String, TestError> = .loading
        switch state {
        case .loading: break
        default: Issue.record("Expected .loading")
        }
    }

    @Test func successPatternMatch() {
        // Verifies that the associated value is correctly extracted during
        // pattern matching.
        let state: Loadable<String, TestError> = .success("hello")
        switch state {
        case .success(let value): #expect(value == "hello")
        default: Issue.record("Expected .success")
        }
    }

    @Test func failurePatternMatch() {
        // Verifies that the associated error is correctly extracted during
        // pattern matching.
        let state: Loadable<String, TestError> = .failure(.sample)
        switch state {
        case .failure(let error): #expect(error == .sample)
        default: Issue.record("Expected .failure")
        }
    }

    // MARK: - Sendable conformance
    // Under Swift 6 strict concurrency, capturing a non-Sendable type inside
    // Task.detached is a compile-time error. A clean build here proves Loadable
    // satisfies Sendable.

    @Test func sendableAcrossTaskBoundary() async {
        // Each case is passed into a detached task (a separate concurrency
        // domain) and the returned value is matched against the original to
        // confirm identity is preserved.
        let states: [Loadable<String, TestError>] = [
            .idle,
            .loading,
            .success("hello"),
            .failure(.sample)
        ]
        for state in states {
            let result = await Task.detached { state }.value
            switch (state, result) {
            case (.idle, .idle), (.loading, .loading): break
            case (.success(let a), .success(let b)): #expect(a == b)
            case (.failure(let a), .failure(let b)): #expect(a == b)
            default: Issue.record("State changed across task boundary")
            }
        }
    }

    // MARK: - run(_:)
    // These tests verify the full state machine driven by run(_:).
    // The .loading transition is synchronous and happens before the first
    // suspension point — reading `state` inside the closure is excluded by
    // Swift's law of exclusivity (run holds a write lock on self). The
    // pre- and post-states are therefore verified around the call instead.
    // run(_:) is nonisolated; the @MainActor annotation below is absent to
    // demonstrate that no specific actor isolation is required.

    @Test func runTransitionsToSuccessOnCompletion() async {
        var state: Loadable<String, TestError> = .idle
        await state.run { "hello" }
        if case .success(let value) = state {
            #expect(value == "hello")
        } else {
            Issue.record("Expected .success after run")
        }
    }

    @Test func runTransitionsToFailureOnThrow() async {
        var state: Loadable<String, TestError> = .idle
        await state.run { @Sendable () throws(TestError) -> String in throw TestError.sample }
        if case .failure(let error) = state {
            #expect(error == .sample)
        } else {
            Issue.record("Expected .failure after run")
        }
    }

    @Test func runWorksFromNonMainActorContext() async {
        // Proves that run(_:) compiles and executes correctly without any
        // actor isolation — callers are not restricted to @MainActor.
        var state: Loadable<String, TestError> = .idle
        await state.run { "world" }
        if case .success(let value) = state {
            #expect(value == "world")
        } else {
            Issue.record("Expected .success from non-MainActor context")
        }
    }

    // MARK: - @Observable compatibility
    // Verifies that a Loadable property on an @Observable class requires no
    // custom property wrappers and that mutations from run(_:) are picked up
    // by withObservationTracking — the same mechanism SwiftUI views use to
    // drive re-renders.

    @Test @MainActor func observablePropertyMutationIsTracked() async {
        let vm = LoadableViewModel()

        // confirmation is Sendable, so it can be called from the @Sendable
        // onChange closure that withObservationTracking requires under
        // Swift 6 strict concurrency.
        await confirmation("state mutation observed") { confirm in
            withObservationTracking {
                _ = vm.state
            } onChange: {
                confirm()
            }

            // onChange fires on the first withMutation call (self = .loading),
            // proving the @Observable contract holds.
            await vm.state.run { "hello" }
        }

        if case .success(let value) = vm.state {
            #expect(value == "hello")
        } else {
            Issue.record("Expected .success after run on @Observable property")
        }
    }

    // MARK: - Equatable
    // Conditional conformance: synthesised when Value: Equatable and
    // Failure: Equatable. Tests cover same-case equality and cross-case
    // inequality.

    @Test func equatableSameCases() {
        #expect(Loadable<String, TestError>.idle == .idle)
        #expect(Loadable<String, TestError>.loading == .loading)
        #expect(Loadable<String, TestError>.success("x") == .success("x"))
        #expect(Loadable<String, TestError>.failure(.sample) == .failure(.sample))
    }

    @Test func equatableDifferentCases() {
        #expect(Loadable<String, TestError>.idle != .loading)
        #expect(Loadable<String, TestError>.success("x") != .success("y"))
    }

    // MARK: - Hashable
    // Conditional conformance: synthesised when Value: Hashable and
    // Failure: Hashable. Verified by inserting duplicates into a Set.

    @Test func hashableDeduplicatesInSet() {
        let set: Set<Loadable<String, TestError>> = [
            .idle, .loading, .idle, .success("x")
        ]
        #expect(set.count == 3)
    }
}

@Observable
private final class LoadableViewModel {
    var state: Loadable<String, TestError> = .idle
}

private enum TestError: Error, Sendable, Equatable, Hashable {
    case sample
}
