//
//  ArchiveEngineSelector.swift
//  Modules
//
//  Created by Stephan Arenswald on 25.11.25.
//

import Foundation
import Swift7zip
import XADMaster
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "engine")

public enum ArchiveEngineType: String, CaseIterable, Identifiable, Sendable, Codable {
    case xad = "XAD (The Unarchiver)"
    case `7zip` = "7-Zip"
    case swc = "SWCompression"
    
    public var id: Self { self }
}

extension ArchiveEngineType {
    public init?(configId: String) {
        switch configId.lowercased() {
        case "xad":  self = .xad
        case "7zip": self = .`7zip`
        case "swc":  self = .swc
        default:     return nil
        }
    }

    /// The catalog `EngineDto.id` for this engine ("xad" | "7zip" | "swc").
    public var configId: String {
        switch self {
        case .xad:  "xad"
        case .`7zip`: "7zip"
        case .swc:  "swc"
        }
    }

    /// Version of the underlying library, for display in the engine info popover.
    ///
    /// All three values are kept honest by `EngineVersionTests`.
    public var libraryVersion: String {
        switch self {
        case .`7zip`:
            // Compiled in from the vendored 7-Zip sources.
            SevenZipArchive.libraryVersion
        case .xad:
            // CFBundleVersion of the embedded XADMaster.framework. Note this is
            // upstream XADMaster's version -- it does not move when the fork's
            // branch revision does. XADMasterVersionString from XADMaster.h is
            // declared but never defined in the shipped binary, so it can't be used.
            Bundle(for: XADArchive.self).infoDictionary?["CFBundleVersion"] as? String ?? "—"
        case .swc:
            // ponytail: hardcoded. SWCompression exposes no version at runtime --
            // its _SWC_VERSION is internal and lives in the `swcomp` executable
            // target, which the library target excludes. EngineVersionTests fails
            // if this drifts from the pin in the workspace Package.resolved; bump
            // it there and here together.
            "4.9.1"
        }
    }
}

public protocol ArchiveEngineSelectorProtocol: Sendable {
    func engine(for id: String) -> ArchiveEngine?
    func engine(for type: ArchiveEngineType) -> ArchiveEngine
    func engineType(for id: String) -> ArchiveEngineType?
}

public struct ArchiveEngineSelector: ArchiveEngineSelectorProtocol {
    private let archiveEngineConfigStore: ArchiveEngineConfigStore
    
    public init(catalog: ArchiveTypeCatalog, configStore: ArchiveEngineConfigStore) {
        archiveEngineConfigStore = configStore
    }
    
    public func engine(for id: String) -> ArchiveEngine? {
        if let engineId = archiveEngineConfigStore.selectedEngine(for: id) {
            log.debug("Using engine: \(engineId)")
            switch engineId {
            case .`7zip`:   return Archive7ZipEngine()
            case .swc:      return ArchiveSwcEngine()
            case .xad:      return ArchiveXadEngine()
            }
        }
        
        return nil
    }
    
    public func engine(for type: ArchiveEngineType) -> ArchiveEngine {
        switch type {
        case .xad:      return ArchiveXadEngine()
        case .swc:      return ArchiveSwcEngine()
        case .`7zip`:     return Archive7ZipEngine()
        }
    }
    
    public func engineType(for id: String) -> ArchiveEngineType? {
        if let engineId = archiveEngineConfigStore.selectedEngine(for: id) {
            log.debug("Using engine: \(engineId)")
            return engineId
        }
        
        return nil
    }
}
