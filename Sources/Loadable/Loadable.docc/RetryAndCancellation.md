# Retry and Cancellation

Retry transient failures with a backoff policy, and hand the state ownership
of the task so loads can be cancelled or superseded.

## Overview

Networks fail transiently, and users navigate away mid-load. Both variants of
`run` and the fire-and-forget `load` accept a ``RetryPolicy``, and
state-owned loads can be cancelled at any point — without ever leaving
``LoadableState/phase`` in a misleading state.

### Retry with a policy

Pass a ``RetryPolicy`` to ``LoadableState/run(retry:shouldRetry:clock:_:)``
and failed attempts are retried for you. ``LoadableState/phase`` stays
`.loading` for the whole sequence — it never flickers to `.failure` between
attempts — and ends `.success` on the first attempt that succeeds, or
`.failure` with the last error once attempts are exhausted:

```swift
@Observable
class UserViewModel {
    var user = LoadableState<User, APIError>()

    func load() async {
        await user.run(retry: .exponential(maxAttempts: 3)) { // 1s, 2s between attempts
            try await api.fetchUser()
        }
    }
}
```

A policy combines three ingredients: the total ``RetryPolicy/maxAttempts``
(including the first), a ``RetryPolicy/Backoff`` strategy (`.none`,
`.fixed(_:)`, or `.exponential(initial:multiplier:max:)`), and an opt-in
``RetryPolicy/jitter`` flag that randomizes each delay to avoid
thundering-herd retries. ``RetryPolicy/exponential(maxAttempts:initial:multiplier:max:jitter:)``
and ``RetryPolicy/fixed(maxAttempts:delay:jitter:)`` cover the common shapes;
``RetryPolicy/never`` — a single attempt — is the default everywhere.

### Skip errors that won't recover

Retrying a `401 Unauthorized` three times just delays the error alert. The
`shouldRetry` closure inspects each thrown error and returns whether another
attempt is worth making:

```swift
await user.run(
    retry: .exponential(maxAttempts: 3),
    shouldRetry: { $0.isTransient }   // fail fast on auth errors
) {
    try await api.fetchUser()
}
```

### Make retry tests instant

Backoff sleeps run on an injectable `any Clock<Duration>` defaulting to
`ContinuousClock()`. Inject a test clock and a three-attempt exponential
sequence completes deterministically with no real waiting:

```swift
@Test func retriesThreeTimes() async {
    let clock = TestClock()   // e.g. from swift-clocks
    async let _ = vm.user.run(retry: .exponential(maxAttempts: 3), clock: clock) {
        try await flakyOperation()
    }
    await clock.advance(by: .seconds(3))   // drains 1s + 2s backoffs
}
```

### Let the state own the task

``LoadableState/run(_:)`` is awaitable and caller-owned — whoever awaits it
holds the task. ``LoadableState/load(retry:shouldRetry:clock:_:)`` is the
fire-and-forget counterpart for `Button` actions, `onAppear`, and
`onChange`, where holding a `Task` is boilerplate. The state owns the task,
and the latest call wins: starting a new `load` cancels the one in flight,
and a stale completion never overwrites the phase of a newer load.

```swift
@Observable
class SearchViewModel {
    var results = LoadableState<[Result], APIError>()

    func search(_ query: String) {
        results.load { try await api.search(query) }   // cancels the previous search
    }

    func cancelSearch() {
        results.cancel()
    }
}
```

`load` returns the driving task as a discardable result — await its `value`
in tests to deterministically wait for completion.

### Cancel without losing state

``LoadableState/cancel()`` stops the in-flight managed load. The operation
observes cooperative cancellation, and ``LoadableState/phase`` immediately
reverts to the value it held before `.loading` — a cancelled refresh never
wipes visible data with a spurious `.failure`:

```swift
ResultsList(phase: viewModel.results.phase)
    .searchable(text: $query)
    .onChange(of: query) { viewModel.search(query) }
    .onDisappear { viewModel.cancelSearch() }
```

Cancelling with no load in flight is a safe no-op. Cancellation during a
backoff sleep aborts the retry sequence immediately. Loads started with the
awaitable `run` are caller-owned and unaffected by `cancel()` — cancel the
task you hold instead, and the same revert semantics apply.
