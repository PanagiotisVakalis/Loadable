//
//  RetryDemoViewModel.swift
//  LoadableExample
//
//  Created by Panagiotis Vakalis on 8/7/26.
//

import Foundation
import Loadable
import Observation

@Observable
@MainActor
final class RetryDemoViewModel {
	var userState = LoadableState<User, Error>()
	private(set) var attempts = 0

	/// Loads with retry: the first two attempts time out, the third succeeds,
	/// with exponential backoff (1s, 2s) between them.
	func loadWithRetry() {
		attempts = 0
		userState.load(
			retry: .exponential(maxAttempts: 3, initial: .seconds(1), multiplier: 2, max: .seconds(4))
		) { [weak self] in
			let attempt = await self?.recordAttempt() ?? 0
			try await Task.sleep(for: .seconds(1))
			if attempt < 3 { throw URLError(.timedOut) }
			return User(name: "Panos")
		}
	}

	/// Cancels the in-flight load; the phase reverts to its pre-loading value.
	func cancel() {
		userState.cancel()
	}

	private func recordAttempt() -> Int {
		attempts += 1
		return attempts
	}
}
