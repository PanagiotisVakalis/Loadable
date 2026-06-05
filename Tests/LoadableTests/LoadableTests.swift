import Testing
import Observation
@testable import Loadable

@MainActor
struct LoadableTests {

    // MARK: - Pattern matching

    @Test func idlePatternMatch() {
        let state = LoadableState<String, TestError>()
        switch state.phase {
        case .idle: break
        default: Issue.record("Expected .idle")
        }
    }

    @Test func successPatternMatch() async {
        let state = LoadableState<String, TestError>()
        await state.run { "hello" }
        switch state.phase {
        case .success(let value): #expect(value == "hello")
        default: Issue.record("Expected .success")
        }
    }

    @Test func failurePatternMatch() async {
        let state = LoadableState<String, TestError>()
        await state.run { @Sendable () throws(TestError) -> String in throw .sample }
        switch state.phase {
        case .failure(let error): #expect(error == .sample)
        default: Issue.record("Expected .failure")
        }
    }

    // MARK: - run(_:)

    @Test func runTransitionsToLoadingThenSuccess() async {
        let state = LoadableState<String, TestError>()

        await confirmation("loading phase observed") { confirm in
            withObservationTracking {
                _ = state.phase
            } onChange: {
                confirm()
            }
            await state.run { "hello" }
        }

        if case .success(let value) = state.phase {
            #expect(value == "hello")
        } else {
            Issue.record("Expected .success after run")
        }
    }

    @Test func runTransitionsToFailureOnThrow() async {
        let state = LoadableState<String, TestError>()
        await state.run { @Sendable () throws(TestError) -> String in throw .sample }
        if case .failure(let error) = state.phase {
            #expect(error == .sample)
        } else {
            Issue.record("Expected .failure after run")
        }
    }

    // MARK: - @Observable compatibility

    @Test func observablePropertyMutationIsTracked() async {
        let vm = UserViewModel()
        let state = vm.userState

        await confirmation("state mutation observed") { confirm in
            withObservationTracking {
                _ = state.phase
            } onChange: {
                confirm()
            }
            await vm.load(shouldFail: false)
        }

        if case .success(let value) = vm.userState.phase {
            #expect(value == "Panos")
        } else {
            Issue.record("Expected .success after load")
        }
    }

    // MARK: - Equatable

    @Test func equatableSameCases() {
        let a = LoadableState<String, TestError>()
        let b = LoadableState<String, TestError>()
        #expect(a.phase == b.phase)
    }

    @Test func equatableDifferentCases() async {
        let a = LoadableState<String, TestError>()
        let b = LoadableState<String, TestError>()
        await b.run { "hello" }
        #expect(a.phase != b.phase)
    }

    // MARK: - Hashable

    @Test func hashableDeduplicatesInSet() async {
        let a = LoadableState<String, TestError>()
        let b = LoadableState<String, TestError>()
        await b.run { "hello" }
        let phases: Set<LoadableState<String, TestError>.Phase> = [
            a.phase, b.phase, a.phase
        ]
        #expect(phases.count == 2)
    }
}

@Observable @MainActor
private final class UserViewModel {
    var userState = LoadableState<String, TestError>()

    func load(shouldFail: Bool) async {
        await userState.run { @Sendable () throws(TestError) -> String in
            if shouldFail { throw .sample }
            return "Panos"
        }
    }
}

private enum TestError: Error, Sendable, Equatable, Hashable {
    case sample
}
