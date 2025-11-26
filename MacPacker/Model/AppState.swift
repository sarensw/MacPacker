//
//  Store.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 23.11.23.
//

import Foundation
import SwiftUI

class AppState: ObservableObject {
    static var shared: AppState = AppState()
    
    private init() { }
    
    //
    // MARK: Observable properties
    //
    
    /// Holds all archives that the app currently takes care of
//    var archives: [UUID: Archive2] = [:]
}
