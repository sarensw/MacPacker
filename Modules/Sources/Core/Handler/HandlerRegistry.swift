//
//  HandlerRegistry.swift
//  Modules
//
//  Created by Stephan Arenswald on 25.11.25.
//


public class HandlerRegistry {
    public private(set) var bindings: [ArchiveTypeId: [HandlerBinding]] = [:]
    public private(set) var overrides: [ArchiveTypeId: ArchiveEngineType] = [:]
    
    public init() {
        bindings[.zip] = [
            HandlerBinding(formatId: .zip, archiveEngineId: .`7zip`, capabilities: [.listContents, .extractFiles], isDefault: true)
        ]
    }
    
    func handlers(for format: ArchiveTypeId) -> [HandlerBinding] {
        return bindings[format] ?? []
    }
    
    func handler(for format: ArchiveTypeId) -> HandlerBinding? {
        let options = handlers(for: format)
        guard !options.isEmpty else { return nil }
        
        if let overrideId = overrides[format],
           let overridden = options.first(where: { $0.archiveEngineId == overrideId }) {
            return overridden
        }
        
        if let `default` = options.first(where: { $0.isDefault }) {
            return `default`
        }
        
        return options.first
    }
    
    func override(engineType: ArchiveEngineType, for format: ArchiveTypeId) {
        overrides[format] = engineType
    }
    
    func clearOverride(for format: ArchiveTypeId) {
        overrides.removeValue(forKey: format)
    }
}
