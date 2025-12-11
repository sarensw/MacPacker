//
//  ArchiveEngineSelector7zip.swift
//  Modules
//
//  Created by Stephan Arenswald on 11.12.25.
//

import Testing
import Foundation
@testable import Core

struct ArchiveEngineSelector7zip: ArchiveEngineSelectorProtocol {
    private var engine = Archive7ZipEngine()
    
    func engine(for id: String) -> (any Core.ArchiveEngine)? {
        return engine
    }
}
