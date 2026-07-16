# Getting Started

Declare a loadable state in your view model, drive it with `run`, and render
its phases in SwiftUI.

## Overview

Add the package to your target — Loadable is SPM-only:

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

### Declare state in your view model

Declare one ``LoadableState`` property per async resource. The container is
itself `@Observable`, so SwiftUI tracks every phase transition with no extra
wiring:

```swift
import Loadable
import Observation

@Observable
class UserViewModel {
    var user = LoadableState<User, APIError>()

    func load() async {
        await user.run { try await api.fetchUser() }
    }
}
```

``LoadableState/run(_:)`` sets ``LoadableState/phase`` to `.loading`
immediately, then to `.success` with the operation's value or `.failure`
with its error. The second generic parameter types the failure: the
operation uses typed throws (`throws(Failure)`), so `case .failure` hands
you an `APIError`, not an `any Error` to cast. Use
`LoadableState<User, any Error>` when you don't need that precision.

### Render the phases

The view switches over a single source of truth — no flags to keep in sync:

```swift
struct UserScreen: View {
    @State private var viewModel = UserViewModel()

    var body: some View {
        Group {
            switch viewModel.user.phase {
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
        .task { await viewModel.load() }
    }
}
```

``LoadableState/Phase`` has exactly four cases:

| Case | Meaning |
| --- | --- |
| `.idle` | Initial state, no load attempted |
| `.loading` | Async operation in progress |
| `.success(Value)` | Operation completed with a value |
| `.failure(Failure)` | Operation failed with a typed error |

`Phase` is `Equatable` and `Hashable` whenever `Value` and `Failure` are,
so phases work in tests, `Set`s, and `onChange(of:)` out of the box.

### Test your view models

`run` is plain `async` — await it and assert on the final phase. The
`.loading` transition is observable through standard Observation tracking:

```swift
@Test func loadSucceeds() async {
    let vm = UserViewModel()
    await vm.load()
    #expect(vm.user.phase == .success(.stub))
}
```

Next, retry transient failures and manage in-flight loads:
<doc:RetryAndCancellation>.
