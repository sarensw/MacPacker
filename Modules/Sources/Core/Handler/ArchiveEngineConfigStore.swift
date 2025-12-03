//
//  HandlerRegistry.swift
//  Modules
//
//  Created by Stephan Arenswald on 25.11.25.
//

import AppKit

public struct EngineOption {
    public let engineId: ArchiveEngineType
    public let capabilities: [ArchiveCapabilities]
}

public struct FormatEngineConfig {
    public let formatId: ArchiveTypeId
    public let options: [EngineOption]
    public var selectedEngineId: ArchiveEngineType
}

private struct PersistedEngineConfig: Codable {
    let formatId: ArchiveTypeId
    let engineId: ArchiveEngineType
}

public class ArchiveEngineConfigStore {
    public private(set) var configs: [ArchiveTypeId: FormatEngineConfig] = [:]
    
    public init() {
        configs[.`7zip`] = FormatEngineConfig(
            formatId: .`7zip`,
            options: [
                EngineOption(engineId: .`7zip`, capabilities: [.listContents, .extractFiles]),
                EngineOption(engineId: .xad, capabilities: [.listContents, .extractFiles])
            ],
            selectedEngineId: .`7zip`
        )
        configs[.zip] = FormatEngineConfig(
            formatId: .zip,
            options: [
                EngineOption(engineId: .`7zip`, capabilities: [.listContents, .extractFiles]),
                EngineOption(engineId: .xad, capabilities: [.listContents, .extractFiles])
            ],
            selectedEngineId: .`7zip`
        )
        
        // override defaults if there are any
        load()
    }
    
    public func selectedEngine(for format: ArchiveTypeId) -> ArchiveEngineType? {
        configs[format]?.selectedEngineId
    }
    
    public func engineOptions(for format: ArchiveTypeId) -> [EngineOption] {
        configs[format]?.options ?? []
    }
    
    public func setSelectedEngine(_ engine: ArchiveEngineType, for format: ArchiveTypeId) {
        guard var config = configs[format] else { return }
        guard config.options.contains(where: { $0.engineId == engine }) else { return }
        config.selectedEngineId = engine
        configs[format] = config
        
        save()
    }
    
    private func save() {
        let userDefaults = UserDefaults.standard
        let cfg = configs.values.map {
            PersistedEngineConfig(formatId: $0.formatId, engineId: $0.selectedEngineId)
        }
        let data = try! JSONEncoder().encode(cfg)
        userDefaults.set(data, forKey: "archiveEngineConfigs")
    }
    
    private func load() {
        let userDefaults = UserDefaults.standard
        guard let data = userDefaults.data(forKey: "archiveEngineConfigs") else { return }
        guard let decoded = try? JSONDecoder().decode([PersistedEngineConfig].self, from: data) else { return }
        
        for config in decoded {
            guard configs[config.formatId] != nil else { continue }
            configs[config.formatId]?.selectedEngineId = config.engineId
        }
    }
}
