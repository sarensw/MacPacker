//
//  ArchivePreviewLoader.swift
//  ArchivePreviewUI
//

import AppKit
import Core

/// Builds a fully-configured `ArchiveState` for previewing an archive.
///
/// Wired exactly like the app's: same catalog, same engine settings, read from
/// the app group so a pick made in Settings ▸ Formats decides the preview too,
/// and automatic mode picks (and falls back) here just like it does there.
///
/// Every engine runs in-process now — the older pin-everything-to-XAD table was
/// there because 7-Zip used to be a subprocess, which an appex cannot spawn.
@MainActor
enum ArchivePreviewLoader {
    static func makeState() -> ArchiveState {
        let catalog = ArchiveTypeCatalog()
        let configStore = ArchiveEngineConfigStore(catalog: catalog, defaults: .macPackerShared)
        let selector = ArchiveEngineSelector(catalog: catalog, configStore: configStore)
        return ArchiveState(catalog: catalog, engineSelector: selector)
    }
}
