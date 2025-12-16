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
}
