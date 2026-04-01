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

import UniformTypeIdentifiers

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
            Logger.error(error)
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
    
    public func allFormatIds() -> [String] {
        return Array(formatById.keys)
    }
    
    public func engineOptions(for formatId: String) -> [EngineDto] {
        return engineOptionsByFormat[formatId] ?? []
    }
    
    public func defaultEngine(for formatId: String) -> ArchiveEngineType? {
        return defaultEngineByFormat[formatId]
    }
    
    
}
