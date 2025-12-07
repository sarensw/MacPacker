//
//  View+Extensions.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 20.10.25.
//
//  Taken from https://www.avanderlee.com/swiftui/conditional-view-modifier/
//

import SwiftUI

extension View {
    /// Applies the given transform if the given condition evaluates to `true`.
    /// - Parameters:
    ///   - condition: The condition to evaluate.
    ///   - transform: The transform to apply to the source `View`.
    /// - Returns: Either the original `View` or the modified `View` if the condition is `true`.
    @ViewBuilder func `if`<Content: View>(_ condition: @autoclosure () -> Bool, transform: (Self) -> Content) -> some View {
        if condition() {
            transform(self)
        } else {
            self
        }
    }
}
