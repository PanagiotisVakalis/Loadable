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

    public init() {}

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
}

extension LoadableState.Phase: Equatable where Value: Equatable, Failure: Equatable {}
extension LoadableState.Phase: Hashable where Value: Hashable, Failure: Hashable {}
