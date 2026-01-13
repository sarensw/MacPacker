//
//  Catalog.swift
//  Modules
//
//  Created by Stephan Arenswald on 08.12.25.
//

public struct CatalogDto: Codable, Sendable {
    public let formats: [ArchiveTypeDto]
    public let compounds: [CompositionTypeDto]
}

// MARK: - Formats

public struct ArchiveTypeDto: Codable, Sendable {
    public let id: String
    public let name: String
    public let kind: String

    public let uti: [String]
    public let extensions: [String]
    public let mime: [String]

    public let rules: [RuleGroupDto]
    public let engines: [EngineDto]
}

// MARK: - Magic Rules

public struct RuleGroupDto: Codable, Sendable {
    public let policy: Policy
    public let tests: [RuleTestDto]

    public enum Policy: String, Codable, Sendable {
        case any
        case all
    }
}

public struct RuleTestDto: Codable, Sendable {
    public let type: String
    public let bytes: [UInt8]
    public let offset: Int

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        offset = try container.decode(Int.self, forKey: .offset)

        // Load the hex string
        let hexString = try container.decode(String.self, forKey: .bytes)
        bytes = RuleTestDto.hexToBytes(hexString)
    }
    
    static func hexToBytes(_ hex: String) -> [UInt8] {
        hex
            .split(whereSeparator: { $0 == " " })
            .compactMap { UInt8($0, radix: 16) }
    }
}


// MARK: - Engine Definitions

public struct EngineDto: Codable, Sendable {
    public let id: String                // engine ID ("xad", "7zip", ...)
    public let capabilities: [String]    // ["listContents", "extractFiles"]
    public let `default`: Bool?          // optional, only present on one item
}

// MARK: - Compounds

public struct CompositionTypeDto: Codable, Sendable {
    public let id: String
    public let name: String

    public let uti: [String]
    public let extensions: [String]

    public let components: [String]      // ["tar", "bzip2"]
}
