//
//  ArchiveTypeCatalogWithDefault.swift
//  Modules
//
//  Created by Stephan Arenswald on 30.07.26.
//

import Testing
import Foundation
@testable import Core

/// The real catalog with the default engine changed for one format.
///
/// Automatic mode always uses the catalog default, so that default is the only
/// thing that decides which engine runs — and therefore the only honest way to
/// set up a fallback test. Pointing rar at XAD makes MacPacker choose an engine
/// that genuinely cannot read a header-encrypted archive, which is exactly the
/// situation the fallback exists for: a default that stops working.
///
/// Today the shipped defaults are good enough that nothing falls back. That is
/// expected to change — 7-Zip ships updates regularly and could regress on a
/// format — so the mechanism is tested by moving the default, not by waiting for
/// a broken one.
final class ArchiveTypeCatalogWithDefault: ArchiveTypeCatalogProtocol {
    private let base = ArchiveTypeCatalog()
    private let overriddenDefaults: [String: ArchiveEngineType]

    /// - Parameter defaults: formatId -> the engine the catalog should call its
    ///   default. Must be one of the format's real engine options.
    init(_ defaults: [String: ArchiveEngineType]) {
        self.overriddenDefaults = defaults
    }

    func allFormatIds() -> [String] {
        base.allFormatIds()
    }

    func engineOptions(for formatId: String) -> [EngineDto] {
        base.engineOptions(for: formatId)
    }

    func defaultEngine(for formatId: String) -> ArchiveEngineType? {
        overriddenDefaults[formatId] ?? base.defaultEngine(for: formatId)
    }
}
