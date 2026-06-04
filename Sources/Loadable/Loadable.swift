public enum Loadable<Value: Sendable, Failure: Error & Sendable>: Sendable {
    case idle
    case loading
    case success(Value)
    case failure(Failure)
}
