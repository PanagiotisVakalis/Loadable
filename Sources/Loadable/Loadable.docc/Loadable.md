# ``Loadable``

Replace scattered `isLoading`, `error`, and `data` variables with a single
`@Observable`-native state machine for async loading.

## Overview

Every MVVM screen ends up hand-rolling the same three variables — a loading
flag, an optional value, an optional error — with no guarantee they stay in
sync. ``LoadableState`` collapses them into one four-state machine that
SwiftUI observes directly:

```swift
import Loadable

@Observable
class UserViewModel {
    var user = LoadableState<User, APIError>()

    func load() async {
        await user.run { try await api.fetchUser() }
    }
}

// In the view:
switch viewModel.user.phase {
case .idle:    Color.clear
case .loading: ProgressView()
case .success(let user): UserView(user: user)
case .failure(let error): ErrorView(error: error)
}
```

Beyond the basics, ``LoadableState/run(retry:shouldRetry:clock:_:)`` retries
transient failures according to a ``RetryPolicy`` without ever flickering to
`.failure` between attempts, and ``LoadableState/load(retry:shouldRetry:clock:_:)``
is the fire-and-forget counterpart whose task the state owns — a newer load
cancels the one in flight, and ``LoadableState/cancel()`` aborts it cleanly.

Start with <doc:GettingStarted>, then add resilience and task management
with <doc:RetryAndCancellation>. The library has zero dependencies, uses
async/await only — no Combine, no UIKit — and its generics are
`Sendable`-constrained throughout for Swift 6 strict concurrency.

## Topics

### Essentials

- <doc:GettingStarted>
- ``LoadableState``

### Retry and cancellation

- <doc:RetryAndCancellation>
- ``RetryPolicy``
