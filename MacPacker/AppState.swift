//
//  AppState.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 22.04.26.
//

import SwiftUI
#if !STORE
import Sparkle
#endif

final class AppState: ObservableObject {
    let updaterController: SPUStandardUpdaterController?
    
    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }
}
