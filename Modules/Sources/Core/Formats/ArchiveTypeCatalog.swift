//
//  ArchiveTypeCatalog.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 01.11.25.
//
// References:
// - https://en.wikipedia.org/wiki/List_of_file_signatures
// - https://gist.github.com/rmorey/b8d1b848086bdce026a9f57732a3b858
// - https://www.digipres.org/formats/mime-types/
// - /System/Library/CoreServices/CoreTypes.bundle/Contents/Info.plist

import Swift7zip
import UniformTypeIdentifiers
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "archive")

public final class ArchiveTypeCatalog: ArchiveTypeCatalogProtocol, Sendable {
    private let formatById: [String: ArchiveTypeDto]
    private let engineOptionsByFormat: [String: [EngineDto]]
    private let defaultEngineByFormat: [String: ArchiveEngineType]
    
    private let catalog: CatalogDto?
    
    public init() {
        let json = Bundle.module.url(forResource: "Catalog", withExtension: "json")
        do {
            let data = try Data(contentsOf: json!)
            let catalog = try JSONDecoder().decode(CatalogDto.self, from: data)
            self.catalog = catalog
            
            var formatById: [String: ArchiveTypeDto] = [:]
            var engineOptionsByFormat: [String: [EngineDto]] = [:]
            var defaultEngineByFormat: [String: ArchiveEngineType] = [:]
            
            for format in catalog.formats {
                formatById[format.id] = format

                engineOptionsByFormat[format.id] = format.engines
                
                if let def = format.engines.first(where: { $0.default == true }) {
                    defaultEngineByFormat[format.id] = ArchiveEngineType(configId: def.id)
                } else if let first = format.engines.first {
                    defaultEngineByFormat[format.id] = ArchiveEngineType(configId: first.id)
                }
            }

            self.formatById = formatById
            self.engineOptionsByFormat = engineOptionsByFormat
            self.defaultEngineByFormat = defaultEngineByFormat
        } catch {
            log.error(error)
            self.catalog = nil
            self.formatById = [:]
            self.engineOptionsByFormat = [:]
            self.defaultEngineByFormat = [:]
        }
    }
    
    public func getAllTypes() -> [ArchiveTypeDto] {
        guard let catalog else { return [] }
        return catalog.formats
    }
    
    public func getType(for id: String) -> ArchiveTypeDto? {
        guard let catalog else { return nil }
        return catalog.formats.first(where: { $0.id == id })
    }
    
    public func getType(where: (ArchiveTypeDto) -> Bool) -> ArchiveTypeDto? {
        guard let catalog else { return nil }
        return catalog.formats.first(where: `where`)
    }
    
    public func allCompositions() -> [CompositionTypeDto] {
        guard let catalog else { return [] }
        return catalog.compounds
    }

    public func allSplits() -> [SplitTypeDto] {
        guard let catalog else { return [] }
        return catalog.splits
    }
    
    public func allFormatIds() -> [String] {
        return Array(formatById.keys)
    }
    
    public func engineOptions(for formatId: String) -> [EngineDto] {
        return engineOptionsByFormat[formatId] ?? []
    }
    
    public func defaultEngine(for formatId: String) -> ArchiveEngineType? {
        return defaultEngineByFormat[formatId]
    }

    // MARK: - What the writer writes

    // The writer names a format as files of it are called — `zip`, `7z` — so the
    // catalog's format for one is the one that lists that name as an extension.

    /// The catalog's format for an archive written as `format`.
    public func type(writtenAs format: CompressionOptions.Format) -> ArchiveTypeDto? {
        getType(where: { $0.extensions.contains(format.rawValue) })
    }

    /// The format a file with the extension `ext` is written in: the writer's
    /// for the catalog's format of that extension — a `jar` is a zip. `nil` when
    /// the catalog has no format for it, or the writer none for that format.
    public func writtenFormat(forExtension ext: String) -> CompressionOptions.Format? {
        guard let type = getType(where: { $0.extensions.contains(ext.lowercased()) }) else { return nil }
        return CompressionOptions.Format.allCases.first { type.extensions.contains($0.rawValue) }
    }
}
