//
//  Store.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 23.11.23.
//

import Foundation
import Observation
import SwiftUI

@Observable
class AppState {
    static var shared: AppState = AppState()
    
    private init() { }
    
    //
    // MARK: Observable properties
    //
    
    /// Holds all archives that the app currently takes care of
    var archives: [UUID: Archive2] = [:]
}
