//
//  ArchiveEngineSelectorSwc.swift
//  Modules
//
//  Created by Stephan Arenswald on 14.12.25.
//

import Testing
import Foundation
@testable import Core

struct ArchiveEngineSelectorSwc: ArchiveEngineSelectorProtocol {
    private var engine = ArchiveSwcEngine()
    
    func engine(for id: String) -> (any Core.ArchiveEngine)? {
        return engine
    }
    
    func engine(for type: Core.ArchiveEngineType) -> any Core.ArchiveEngine {
        return engine
    }
    
    func engineType(for id: String) -> Core.ArchiveEngineType? {
        return .swc
    }
}
