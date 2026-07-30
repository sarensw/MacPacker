//
//  PinnedEngineSelector.swift
//  Modules
//
//  Created by Stephan Arenswald on 30.07.26.
//

import Foundation

/// A selector that overrides the configured engine for specific formats.
///
/// The catalog lists several engines per format and the user picks one, but the
/// pick can be wrong for an individual archive: XAD is a valid engine for `rar`
/// and `7zip`, yet it cannot open a header-encrypted archive of either, because
/// the header has to be decrypted during `XADArchive` init and XADArchive only
/// takes a password afterwards.
///
/// When `ArchiveLoader` has to fall back to another engine to read an archive,
/// `ArchiveState` pins that engine here for the rest of the window. Without it
/// the archive would list through the fallback and then fail on the first
/// extraction, which resolves the engine from the format all over again.
struct PinnedEngineSelector: ArchiveEngineSelectorProtocol {
    let base: any ArchiveEngineSelectorProtocol
    /// formatId -> engine that actually works for the archive in this window.
    let pinned: [String: ArchiveEngineType]

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
