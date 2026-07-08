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

#Preview {
    ContentView()
}
