public enum Loadable<Value: Sendable, Failure: Error & Sendable>: Sendable {
    case idle
    case loading
    case success(Value)
    case failure(Failure)

    // The operation closure uses typed throws (throws(Failure)) rather than
    // untyped throws. This makes Failure a compile-time constraint: the caught
    // error is already typed as Failure, so no runtime cast is needed and no
    // fallback strategy is required. Callers whose async work throws a different
    // error type must map it to Failure at the call site before invoking run(_:).
    // Isolation is the caller's responsibility: call from @MainActor for view
    // models, or from within a custom actor's isolation for background services.
    public mutating func run(
        _ operation: @Sendable () async throws(Failure) -> Value
    ) async {
        self = .loading
        do {
            self = try await .success(operation())
        } catch {
            self = .failure(error)
        }
    }
}

extension Loadable: Equatable where Value: Equatable, Failure: Equatable {}
extension Loadable: Hashable where Value: Hashable, Failure: Hashable {}
