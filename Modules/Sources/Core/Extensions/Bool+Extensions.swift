//
//  Bool+Extensions.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 20.10.25.
//
//  Inspired by https://www.avanderlee.com/swiftui/conditional-view-modifier/
//

extension Bool {
    public static var macOS13: Bool {
        if #available(macOS 14, *) {
            return false   // On macOS 14 or later
        } else {
            return true    // On macOS 13 or earlier
        }
    }
}
