import Testing
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
}

private enum TestError: Error, Sendable, Equatable {
    case sample
}
