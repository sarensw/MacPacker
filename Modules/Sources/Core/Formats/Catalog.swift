//
//  Catalog.swift
//  Modules
//
//  Created by Stephan Arenswald on 08.12.25.
//

public struct CatalogDto: Codable, Sendable {
    public let formats: [ArchiveTypeDto]
    public let compounds: [CompositionTypeDto]
    public let splits: [SplitTypeDto]
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

// MARK: - Split / Multi-Volume

/// A split / multi-volume "type" — modeled exactly like a compound: a file name
/// that points back to a base `format`, plus how to recognize it and how to find
/// the first volume. Detection is name-first (`pattern`), with an optional content
/// `marker` for the one case a name can't settle — a bare `.zip` that is really
/// the terminal piece of a spanned set. The engine only declares `splitVolumes`.
public struct SplitTypeDto: Codable, Sendable {
    public let id: String
    public let name: String
    /// The base format this is a split of ("zip", …).
    public let format: String
    /// Scheme identifier: "spanned" | "numeric".
    public let scheme: String
    /// File-name regex; a match means the file is a volume part of this type.
    public let pattern: String
    /// Optional content signal for when the name can't decide (the bare `.zip`
    /// terminal volume): find `bytes` near the tail, then test a field.
    public let marker: SplitMarkerDto?
    /// How to derive the first volume's name from *any* part (regex substitution) —
    /// what the engine is actually pointed at, e.g. spanned → `.z01`.
    public let firstVolume: FirstVolumeDto
    /// **Window-identity** label (purely lexical): the volume suffix (matched by `pattern`)
    /// is replaced with this to give every part of a set the same dedup key. Chosen
    /// so the ambiguous parts collapse too — spanned → `.zip` (which the bare
    /// terminal already is), numeric → `.zip.001`. Distinct from `firstVolume`.
    public let label: String
}

/// Content signal: locate `bytes` (a signature) in the file's tail, then test a
/// field relative to it — e.g. the zip EOCD "number of this disk", non-zero when
/// the archive spans more than one volume.
public struct SplitMarkerDto: Codable, Sendable {
    public let bytes: [UInt8]
    public let field: SplitFieldDto

    enum CodingKeys: String, CodingKey { case bytes, field }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let hex = try c.decode(String.self, forKey: .bytes)
        bytes = hex.split(separator: " ").compactMap { UInt8($0, radix: 16) }
        field = try c.decode(SplitFieldDto.self, forKey: .field)
    }
}

public struct SplitFieldDto: Codable, Sendable {
    public let offset: Int
    public let length: Int
    public let match: String   // "nonzero" → the field must be non-zero to match
}

/// A regex substitution turning any volume part's file name into the first
/// volume's name (the one the engine is pointed at).
public struct FirstVolumeDto: Codable, Sendable {
    public let pattern: String
    public let replacement: String
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
    public let type: String            // "signature" | "end_signature"
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
    public let capabilities: [String]    // ["listContents", "extractFiles", "splitVolumes"]
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
