//
//  RetryDemoView.swift
//  LoadableExample
//
//  Created by Panagiotis Vakalis on 8/7/26.
//

import SwiftUI
import Loadable

struct RetryDemoView: View {
	@State private var vm = RetryDemoViewModel()

	var body: some View {
		VStack(spacing: 20) {
			switch vm.userState.phase {
			case .idle:
				Text("Idle — tap Load")
			case .loading:
				ProgressView("Loading… attempt \(vm.attempts) of 3")
			case .success(let user):
				Text("✅ Hello, \(user.name)! (succeeded on attempt \(vm.attempts))")
			case .failure(let error):
				Text("❌ Error: \(error.localizedDescription)")
			}

			Button("Load (fails twice, then succeeds)") {
				vm.loadWithRetry()
			}
			Button("Cancel", role: .destructive) {
				vm.cancel()
			}
		}
		.padding()
	}
}

#Preview {
    RetryDemoView()
}
