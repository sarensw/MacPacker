//
//  ArchiveEngineSelectorXad.swift
//  Modules
//
//  Created by Stephan Arenswald on 11.12.25.
//

import Testing
import Foundation
@testable import Core

struct ArchiveEngineSelectorXad: ArchiveEngineSelectorProtocol {
    private var engine = ArchiveXadEngine()
    
    func engine(for id: String) -> (any Core.ArchiveEngine)? {
        return engine
    }
}
