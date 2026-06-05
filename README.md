# Loadable

[![CI](https://github.com/pvbrew/Loadable/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/pvbrew/Loadable/actions/workflows/ci.yml)

A lightweight, zero-dependency Swift 6 library which replaces scattered `isLoading`, `error`, and `data` variables with a single `@Observable`-compatible `Loadable` enum — built for SwiftUI MVVM and async/await.

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

Three variables which must stay in sync, with no guarantee they will. `Loadable` collapses them into one.

---

## The Solution

```swift
@Observable class UserViewModel {
    var userState = Loadable<User, AppError>.idle

    func loadUser() async {
        await userState.run { try await api.fetchUser() }
    }
}
```

Your view switches on a single source of truth:

```swift
switch viewModel.userState {
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

- iOS 17+
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
    .package(url: "https://github.com/pvbrew/Loadable", from: "1.0.0")
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
    var userState = Loadable<User, AppError>.idle

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
            switch viewModel.userState {
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

### States

| Case | Description |
|------|-------------|
| `.idle` | Initial state, no load attempted |
| `.loading` | Async operation in progress |
| `.success(Value)` | Operation completed successfully |
| `.failure(Failure)` | Operation failed with a typed error |

---

## Design Goals

- **Zero dependencies** — nothing to conflict with your existing stack
- **Swift 6 concurrency-safe** — `Sendable`-constrained generics throughout
- **`@Observable` compatible** — works natively with SwiftUI's observation system
- **No Combine, no UIKit** — async/await only

---

## Roadmap

- **v1** — Core `Loadable` enum + `.run {}` mutation
- **v2** — Retry policies, cancellation helpers
- **v3** — Pagination states, combined/zipped states
- **v4** — Swift Macro shortcuts for boilerplate reduction

---

## License

MIT. See [LICENSE](LICENSE) for details.
