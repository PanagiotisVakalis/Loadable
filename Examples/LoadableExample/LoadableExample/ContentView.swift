//
//  ContentView.swift
//  LoadableExample
//
//  Created by Panagiotis Vakalis on 5/6/26.
//

import SwiftUI
import Loadable

struct ContentView: View {
	var body: some View {
		TabView {
			Tab("Basic", systemImage: "arrow.down.circle") {
				BasicDemoView()
			}
			Tab("Retry & Cancel", systemImage: "arrow.clockwise.circle") {
				RetryDemoView()
			}
		}
	}
}

struct BasicDemoView: View {
	@State private var vm = UserViewModel()

	var body: some View {
		VStack(spacing: 20) {
			switch vm.userState.phase {
			case .idle:
				Text("Idle — tap a button")
			case .loading:
				ProgressView("Loading…")
			case .success(let user):
				Text("✅ Hello, \(user.name)!")
			case .failure(let error):
				Text("❌ Error: \(error.localizedDescription)")
			}

			Button("Load (success)") {
				Task { await vm.load(shouldFail: false) }
			}
			Button("Load (fail)") {
				Task { await vm.load(shouldFail: true) }
			}
		}
		.padding()
	}
}

#Preview {
    ContentView()
}
