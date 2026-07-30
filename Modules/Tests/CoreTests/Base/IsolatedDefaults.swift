//
//  IsolatedDefaults.swift
//  Modules
//
//  Created by Stephan Arenswald on 30.07.26.
//

import Foundation

/// A throwaway `UserDefaults` suite, empty and unique per call.
///
/// Tests never write to `UserDefaults.standard`: it is the real user's settings
/// on a dev machine, it leaks between test cases, and it makes results depend on
/// whatever the machine happens to have configured. Anything that persists takes
/// its store by injection instead, and gets one of these.
func isolatedDefaults(_ label: String = #function) -> UserDefaults {
    let suite = "MacPackerTests.\(label).\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else {
        fatalError("could not create an isolated defaults suite")
    }
    defaults.removePersistentDomain(forName: suite)
    return defaults
}
