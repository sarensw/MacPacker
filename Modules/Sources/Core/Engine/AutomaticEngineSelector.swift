//
//  AutomaticEngineSelector.swift
//  Modules
//
//  Created by Stephan Arenswald on 30.07.26.
//

import Foundation

/// A selector that overrides the chosen engine for specific formats.
///
/// The catalog lists several engines per format and the user picks one, but the
/// pick can be wrong for an individual archive: XAD is a valid engine for `rar`
/// and `7zip`, yet it cannot open a header-encrypted archive of either, because
/// the header has to be decrypted during `XADArchive` init and XADArchive only
/// takes a password afterwards.
///
/// In automatic mode `ArchiveLoader` may fall back to another engine to read an
/// archive; `ArchiveState` then pins that engine here for the rest of the
/// window. Without it the archive would list through the fallback and then fail
/// on the first extraction, which resolves the engine from the format all over
/// again. Fallback stays on so the pinned engine keeps its own alternatives.
struct AutomaticEngineSelector: ArchiveEngineSelectorProtocol {
    let base: any ArchiveEngineSelectorProtocol
    /// formatId -> engine that actually works for the archive in this window.
    let pinned: [String: ArchiveEngineType]

    var allowsEngineFallback: Bool { base.allowsEngineFallback }

    func engine(for id: String) -> ArchiveEngine? {
        guard let type = pinned[id] else { return base.engine(for: id) }
        return base.engine(for: type)
    }

    func engine(for type: ArchiveEngineType) -> ArchiveEngine {
        base.engine(for: type)
    }

    func engineType(for id: String) -> ArchiveEngineType? {
        pinned[id] ?? base.engineType(for: id)
    }
}
