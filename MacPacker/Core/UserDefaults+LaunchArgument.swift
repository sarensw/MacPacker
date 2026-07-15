//
//  UserDefaults+LaunchArgument.swift
//  MacPacker
//
//  Created by Claude on 14.07.26.
//

import Foundation

extension UserDefaults {
    /// The value of a launch argument (`-key value`) taken from the **argument
    /// domain only** — i.e. the actual command line for this launch (`open -a
    /// MacPacker --args -key value`, or the arguments a relaunch passes through
    /// `NSWorkspace`). Unlike `string(forKey:)`, this never falls back to a
    /// persisted preference, so a launch parameter can't linger into a later
    /// normal launch.
    func launchArgument(_ key: String) -> String? {
        volatileDomain(forName: UserDefaults.argumentDomain)[key] as? String
    }
}
