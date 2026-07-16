# Loadable

[![CI](https://github.com/pvbrew/Loadable/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/pvbrew/Loadable/actions/workflows/ci.yml)
[![Documentation](https://img.shields.io/badge/docs-DocC-blue)](https://pvbrew.github.io/Loadable/)
[![License: MIT](https://img.shields.io/badge/license-MIT-lightgrey)](LICENSE)

A lightweight, zero-dependency Swift 6 library which replaces scattered `isLoading`, `error`, and `data` variables with a single `@Observable`-native `LoadableState` — built for SwiftUI MVVM and async/await.

---

## The Problem

Every MVVM app ends up writing some version of this:

```swift
@Observable class UserViewModel {
    var isLoading = false
    var user: User?
    var error: AppError?

    func loadUser() async {
        isLoading = true
        do {
            user = try await api.fetchUser()
        } catch {
            self.error = error as? AppError
        }
        isLoading = false
    }
}
```

Three variables which must stay in sync, with no guarantee they will. `LoadableState` collapses them into one.

---

## The Solution

```swift
@Observable class UserViewModel {
    var userState = LoadableState<User, AppError>()

    func loadUser() async {
        await userState.run { try await api.fetchUser() }
    }
}
```

Your view switches on a single source of truth:

```swift
switch viewModel.userState.phase {
case .idle:
    Color.clear
case .loading:
    ProgressView()
case .success(let user):
    UserView(user: user)
case .failure(let error):
    ErrorView(error: error)
}
```

---

## Requirements

- iOS 17+ / macOS 14+ / tvOS 17+ / watchOS 10+ / visionOS 1+
- Swift 6
- Xcode 16+

---

## Installation

### Swift Package Manager

In Xcode: **File → Add Package Dependencies** and enter the repository URL:

```
https://github.com/pvbrew/Loadable
```

Or add it manually to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/pvbrew/Loadable", from: "2.1.0")
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: ["Loadable"]
    )
]
```

---

## Usage

### Define state in your ViewModel

```swift
import Loadable
import Observation

@Observable class UserViewModel {
    var userState = LoadableState<User, AppError>()

    func loadUser() async {
        await userState.run { try await api.fetchUser() }
    }
}
```

### Consume it in your View

```swift
struct UserScreen: View {
    @State private var viewModel = UserViewModel()

    var body: some View {
        Group {
            switch viewModel.userState.phase {
            case .idle:
                Color.clear
            case .loading:
                ProgressView()
            case .success(let user):
                UserView(user: user)
            case .failure(let error):
                ErrorView(error: error)
            }
        }
        .task { await viewModel.loadUser() }
    }
}
```

### Phases

| Case | Description |
|------|-------------|
| `.idle` | Initial state, no load attempted |
| `.loading` | Async operation in progress |
| `.success(Value)` | Operation completed successfully |
| `.failure(Failure)` | Operation failed with a typed error |

---

## Retry

Pass a `RetryPolicy` to `run` and transient failures are retried for you — `phase` stays `.loading` for the whole sequence, with no flicker to `.failure` between attempts:

```swift
@Observable class UserViewModel {
    var userState = LoadableState<User, AppError>()

    func loadUser() async {
        await userState.run(
            retry: .exponential(maxAttempts: 3),   // 1s, 2s between attempts
            shouldRetry: { $0.isTransient }        // skip retries for e.g. 401s
        ) {
            try await api.fetchUser()
        }
    }
}
```

```swift
struct UserScreen: View {
    @State private var viewModel = UserViewModel()

    var body: some View {
        UserContent(phase: viewModel.userState.phase)
            .task { await viewModel.loadUser() }   // retries happen inside
    }
}
```

Build your own policy from `maxAttempts`, a backoff strategy (`.none`, `.fixed`, or `.exponential(initial:multiplier:max:)`), and an opt-in full-jitter flag. `RetryPolicy.never` — a single attempt — is the default everywhere and matches v1 behaviour exactly.

Backoff sleeps use an injectable `any Clock<Duration>` (defaulting to `ContinuousClock()`), so your own view-model tests can pass a test clock and run instantly.

---

## Cancellation

`load` is the fire-and-forget counterpart to `run`: the state owns the task, so buttons and `onAppear` don't need to hold one. `cancel()` stops the in-flight load, and starting a new `load` cancels the previous one first — the latest call always wins, even if an older operation finishes late:

```swift
@Observable class SearchViewModel {
    var results = LoadableState<[Result], AppError>()

    func search(_ query: String) {
        results.load { try await api.search(query) } // cancels the previous search
    }

    func cancelSearch() {
        results.cancel()
    }
}
```

```swift
struct SearchScreen: View {
    @State private var viewModel = SearchViewModel()

    var body: some View {
        ResultsList(phase: viewModel.results.phase)
            .searchable(text: $query)
            .onChange(of: query) { viewModel.search(query) }
            .onDisappear { viewModel.cancelSearch() }
    }
}
```

A cancelled load never sets `.failure` — `phase` reverts to the value it held before `.loading`, so stale data stays visible after a cancelled refresh. `load` also accepts the same `retry:` policy as `run`, and cancelling during a backoff sleep aborts the retry sequence immediately. The awaitable `run` stays caller-owned and un-managed, so both styles coexist.

---

## Design Goals

- **Zero dependencies** — nothing to conflict with your existing stack
- **Swift 6 concurrency-safe** — `Sendable`-constrained generics throughout
- **`@Observable` native** — `LoadableState` is itself `@Observable`, so every phase transition is automatically tracked by SwiftUI with no extra wiring
- **No Combine, no UIKit** — async/await only

---

## Roadmap

- **v1** — Core `Loadable` enum + `.run {}` mutation
- **v2** — Retry policies, cancellation helpers
- **v3** — Pagination states, combined/zipped states
- **v4** — Swift Macro shortcuts for boilerplate reduction

---

## Example

An example SwiftUI app demonstrating all four `Loadable` states is available in [`Examples/LoadableExample`](Examples/LoadableExample).

---

## Documentation

Hosted documentation lives at **[pvbrew.github.io/Loadable](https://pvbrew.github.io/Loadable/)** — start with [Getting Started](https://pvbrew.github.io/Loadable/documentation/loadable/gettingstarted) and [Retry and Cancellation](https://pvbrew.github.io/Loadable/documentation/loadable/retryandcancellation). The DocC catalog also ships with the package: open the Loadable scheme in Xcode and run **Product ▸ Build Documentation**, or read the articles as markdown in [`Sources/Loadable/Loadable.docc`](Sources/Loadable/Loadable.docc).

---

## License

MIT. See [LICENSE](LICENSE) for details.
