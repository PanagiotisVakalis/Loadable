//
//  UserViewModel.swift
//  LoadableExample
//
//  Created by Panagiotis Vakalis on 5/6/26.
//

import Foundation
import Loadable
import Observation

@Observable
class UserViewModel {
	var userState = LoadableState<User, Error>()
	
	func load(shouldFail: Bool) async {
		await userState.run {
			try await Task.sleep(for: .seconds(2))
			if shouldFail { throw URLError(.badServerResponse) }
			return User(name: "Panos")
		}
	}
}
