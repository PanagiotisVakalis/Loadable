public enum Loadable<Value: Sendable, Failure: Error & Sendable>: Sendable {
    case idle
    case loading
    case success(Value)
    case failure(Failure)

    @MainActor
    public mutating func run(
        _ operation: () async throws(Failure) -> Value
    ) async {
        self = .loading
        do {
            self = try await .success(operation())
        } catch {
            self = .failure(error)
        }
    }
}
