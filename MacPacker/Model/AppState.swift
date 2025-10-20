//
//  Store.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 23.11.23.
//

import Foundation
import KeyboardShortcuts
import SwiftUI

class AppState: ObservableObject {
    static var shared: AppState = AppState()
    
    private init() { }
    
    //
    // MARK: Observable properties
    //
    
    /// Holds all archives that the app currently takes care of
    var archives: [UUID: Archive2] = [:]
}

extension KeyboardShortcuts.Name {
    static let spacePreview = Self("spacePreview", default: .init(.space, modifiers: []))
}

extension AppState {
    func setUpEvents() {
        KeyboardShortcuts.onKeyUp(for: .spacePreview) {
            print("Space Preview")
//            if let archive = state.archive,
//               let selectedItem = state.selectedItems.first,
//               let url = archive.extractFileToTemp(selectedItem) {
//                appDelegate.openPreviewerWindow(for: url)
//            }
//            return .handled
        }
    }
}
