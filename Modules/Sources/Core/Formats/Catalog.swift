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
/// the first volume. Detection is name-first (`pattern`), with optional content
/// `markers` for the one case a name can't settle — a bare `.zip` that is really
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
    /// The record that ends the file, which the `markers` read around: the last
    /// occurrence of its signature with room for its `length` after it.
    public let endRecord: SplitEndRecordDto?
    /// Optional content signals for when the name can't decide (the bare `.zip`
    /// terminal volume): each tests a field relative to the `endRecord`; any one
    /// that matches is enough.
    public let markers: [SplitMarkerDto]?
    /// How to derive the first volume's name from *any* part (regex substitution) —
    /// what the engine is actually pointed at, e.g. spanned → `.z01`.
    public let firstVolume: FirstVolumeDto
    /// **Window-identity** label (purely lexical): the volume suffix (matched by `pattern`)
    /// is replaced with this to give every part of a set the same dedup key. Chosen
    /// so the ambiguous parts collapse too — spanned → `.zip` (which the bare
    /// terminal already is), numeric → `.zip.001`. Distinct from `firstVolume`.
    public let label: String
}

/// The record a format ends its files with — the zip EOCD: its signature and
/// its fixed `length`. The file's own is the last occurrence with room for the
/// whole record after it, the one 7-Zip reads too; an earlier one belongs to an
/// archive the file stores.
public struct SplitEndRecordDto: Codable, Sendable {
    public let bytes: [UInt8]
    public let length: Int

    enum CodingKeys: String, CodingKey { case bytes, length }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bytes = RuleTestDto.hexToBytes(try c.decode(String.self, forKey: .bytes))
        length = try c.decode(Int.self, forKey: .length)
    }
}

/// Content signal: a field relative to the end record — e.g. the zip EOCD
/// "number of this disk", non-zero when the archive spans more than one volume.
/// In Zip64 that field can be all ones, "see the Zip64 records"; Zip64's locator,
/// right before the EOCD, then says how many volumes there are.
public struct SplitMarkerDto: Codable, Sendable {
    /// Optional: a signature that must sit `offset` bytes from the end record —
    /// Zip64's locator, 20 bytes before the EOCD.
    public let with: SplitSignatureDto?
    public let field: SplitFieldDto
}

public struct SplitSignatureDto: Codable, Sendable {
    public let offset: Int
    public let bytes: [UInt8]

    enum CodingKeys: String, CodingKey { case offset, bytes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        offset = try c.decode(Int.self, forKey: .offset)
        bytes = RuleTestDto.hexToBytes(try c.decode(String.self, forKey: .bytes))
    }
}

public struct SplitFieldDto: Codable, Sendable {
    public let offset: Int
    public let length: Int
    /// "nonzeroBelowMax" → the field is neither zero nor all ones, a value that
    /// stands for one kept elsewhere; "aboveOne" → read little-endian, as zip
    /// stores numbers, it is 2 or more
    public let match: String
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

    /// Whether the engine writes archives of its format, so one it opened can be
    /// changed. An engine that only reads numbers entries its own way, and the
    /// writer would take those numbers for other entries.
    public var canEdit: Bool { capabilities.contains("edit") }
}

// MARK: - Compounds

public struct CompositionTypeDto: Codable, Sendable {
    public let id: String
    public let name: String

    public let uti: [String]
    public let extensions: [String]

    public let components: [String]      // ["tar", "bzip2"]
}
