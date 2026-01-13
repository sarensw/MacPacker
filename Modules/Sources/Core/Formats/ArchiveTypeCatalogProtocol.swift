//
//  ArchiveTypeCatalogProtocol.swift
//  Modules
//
//  Created by Stephan Arenswald on 08.12.25.
//


public protocol ArchiveTypeCatalogProtocol: AnyObject, Sendable {
    /// All known format IDs (JSON `formats[].id`)
    func allFormatIds() -> [String]

    /// Engine options defined in the JSON for this format.
    func engineOptions(for formatId: String) -> [EngineDto]

    /// Default engine for this format as defined in the JSON.
    func defaultEngine(for formatId: String) -> ArchiveEngineType?
}
