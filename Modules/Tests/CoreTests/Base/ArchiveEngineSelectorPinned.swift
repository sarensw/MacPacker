//
//  ArchiveEngineSelectorPinned.swift
//  Modules
//
//  Created by Stephan Arenswald on 30.07.26.
//

import Testing
import Foundation
@testable import Core

/// Selects one engine for every format, but can still vend any engine when asked
/// for a specific `ArchiveEngineType`.
///
/// The single-engine helpers (`ArchiveEngineSelector7zip` and friends) answer
/// *every* call with their one engine, including `engine(for type:)`. That makes
/// them unusable for anything that reaches past the selected engine — a fallback
/// asking for 7-Zip by type would be handed XAD right back.
///
/// This models what the production `ArchiveEngineSelector` does: the user's pick
/// decides the format, but the engines themselves stay individually reachable.
/// It takes the pick as a parameter instead of reading `UserDefaults`, so tests
/// never depend on machine state or on each other's ordering.
struct ArchiveEngineSelectorPinned: ArchiveEngineSelectorProtocol {
    let selected: ArchiveEngineType

    private let sevenZip = Archive7ZipEngine()
    private let xad = ArchiveXadEngine()
    private let swc = ArchiveSwcEngine()

    init(_ selected: ArchiveEngineType) {
        self.selected = selected
    }

    func engine(for id: String) -> (any ArchiveEngine)? {
        engine(for: selected)
    }

    func engine(for type: ArchiveEngineType) -> any ArchiveEngine {
        switch type {
        case .`7zip`: return sevenZip
        case .xad: return xad
        case .swc: return swc
        }
    }

    func engineType(for id: String) -> ArchiveEngineType? {
        selected
    }
}
