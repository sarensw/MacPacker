//
//  ArchivePreviewLoader.swift
//  ArchivePreviewUI
//

import AppKit
import Core

/// A read-only selector for the engines that are safe inside Quick Look.
///
/// Do not express these pins through `ArchiveEngineConfigStore`: automatic
/// selection intentionally ignores stored overrides, and writing them also
/// leaks preview-only choices into the in-app debug harness's user settings.
private struct ArchivePreviewEngineSelector: ArchiveEngineSelectorProtocol {
    let base: ArchiveEngineSelector
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

        // tar.xz previewing opts into 7-Zip's nested-stream path so it can scan
        // the inner tar without staging it or allocating 7-Zip's whole-XZ-block
        // seek cache. Staged XAD compounds remain pinned below; ArchiveLoader
        // makes those cancellable through their extraction progress callback.
        let selector = ArchivePreviewEngineSelector(
            base: ArchiveEngineSelector(catalog: catalog, configStore: configStore),
            pinned: [
                "7zip": .xad,
                "bzip2": .xad,
                "cab": .xad,
                "cpio": .xad,
                "gzip": .xad,
                "iso": .xad,
                "lha": .xad,
                "lz4": .swc,
                "lzx": .xad,
                "rar": .xad,
                "rpm": .xad,
                "sea": .xad,
                "sit": .xad,
                "sitx": .xad,
                "tar": .xad,
                "xar": .xad,
                "xz": .`7zip`,
                "z": .xad,
                "zip": .xad,
                "zipx": .xad
            ]
        )
        return ArchiveState(
            catalog: catalog,
            engineSelector: selector,
            compoundLoadingStrategy: .streamed
        )
    }
}
