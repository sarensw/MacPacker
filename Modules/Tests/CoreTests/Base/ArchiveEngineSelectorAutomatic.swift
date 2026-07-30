//
//  ArchiveEngineSelectorAutomatic.swift
//  Modules
//
//  Created by Stephan Arenswald on 30.07.26.
//

import Testing
import Foundation
@testable import Core

/// Models automatic mode: one engine is chosen for every format, any engine is
/// still reachable by `ArchiveEngineType`, and the loader may fall back.
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
struct ArchiveEngineSelectorAutomatic: ArchiveEngineSelectorProtocol {
    let selected: ArchiveEngineType
    /// Automatic mode is what makes fallback legal, so this double opts in. The
    /// single-engine doubles inherit the protocol default (false) and stay
    /// strict, which is what makes them able to assert an engine's real limits.
    let allowsEngineFallback = true

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
