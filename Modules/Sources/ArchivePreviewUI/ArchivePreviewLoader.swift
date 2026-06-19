//
//  ArchivePreviewLoader.swift
//  ArchivePreviewUI
//

import AppKit
import Core

/// Builds a fully-configured `ArchiveState` for previewing an archive.
///
/// QuickLook extensions can't spawn subprocesses, so every format is pinned to a
/// library-backed engine (`xad`, plus `swc` for lz4). This is the single place
/// the QuickLook extension and the in-app debug harness share, so both behave
/// identically — change an engine pin here and both pick it up.
@MainActor
enum ArchivePreviewLoader {
    static func makeState() -> ArchiveState {
        let catalog = ArchiveTypeCatalog()
        let configStore = ArchiveEngineConfigStore(catalog: catalog)

        // NOTE: 7-Zip now runs in-process (Swift7zip, no subprocess), so the
        // preview could use the native `.7zip` engine instead of pinning these
        // to `.xad`. Switching them over is tracked as a separate follow-up.
        configStore.setSelectedEngine(.xad, for: "7zip")
        configStore.setSelectedEngine(.xad, for: "bzip2")
        configStore.setSelectedEngine(.xad, for: "cab")
        configStore.setSelectedEngine(.xad, for: "cpio")
        configStore.setSelectedEngine(.xad, for: "gzip")
        configStore.setSelectedEngine(.xad, for: "iso")
        configStore.setSelectedEngine(.xad, for: "lha")
        configStore.setSelectedEngine(.swc, for: "lz4")
        configStore.setSelectedEngine(.xad, for: "lzx")
        configStore.setSelectedEngine(.xad, for: "rar")
        configStore.setSelectedEngine(.xad, for: "rpm")
        configStore.setSelectedEngine(.xad, for: "sea")
        configStore.setSelectedEngine(.xad, for: "sit")
        configStore.setSelectedEngine(.xad, for: "sitx")
        configStore.setSelectedEngine(.xad, for: "tar")
        configStore.setSelectedEngine(.xad, for: "xar")
        configStore.setSelectedEngine(.xad, for: "xz")
        configStore.setSelectedEngine(.xad, for: "z")
        configStore.setSelectedEngine(.xad, for: "zip")
        configStore.setSelectedEngine(.xad, for: "zipx")

        let selector = ArchiveEngineSelector(catalog: catalog, configStore: configStore)
        return ArchiveState(catalog: catalog, engineSelector: selector)
    }
}
