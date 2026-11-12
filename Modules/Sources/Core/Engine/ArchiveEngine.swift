//
//  ArchiveEngine.swift
//  Modules
//
//  Created by Stephan Arenswald on 25.11.25.
//

import Foundation

/// Describes the status of the engine when opening or extracting or doing any
/// work in general.
public enum EngineStatus: Sendable {
    public enum ProcessingActivity: Sendable {
        case loadingEngine(typeID: String)
        case engineLoaded(name: String, typeID: String?)
        case temporaryDirectoryCreated(URL)
        case entriesFound(Int)
        case entryExtracted(URL)
        case splitFirstVolume(String)
        case archiveURLLost(typeID: String)
        case invalidArchiveType(typeID: String)
        case buildingTree
    }

    case cancelled
    case idle
    case processing(progress: Double?, activity: ProcessingActivity)
    case done
    case error(Error)
}

public struct ArchiveEngineLoadResult: Sendable {
    let items: [UUID: ArchiveItem]
    let hasTree: Bool
    let uncompressedSize: Int64
    /// True when at least one entry is encrypted, so the UI can show the lock
    /// indicator before anything is extracted.
    let isEncrypted: Bool
    /// What the names were read in, for an archive that does not say itself.
    /// `nil` for one that does: there is nothing to choose then.
    let nameEncoding: ArchiveNameEncoding?

    init(
        items: [UUID: ArchiveItem],
        hasTree: Bool,
        uncompressedSize: Int64,
        isEncrypted: Bool = false,
        nameEncoding: ArchiveNameEncoding? = nil
    ) {
        self.items = items
        self.hasTree = hasTree
        self.uncompressedSize = uncompressedSize
        self.isEncrypted = isEncrypted
        self.nameEncoding = nameEncoding
    }
}

public struct ArchiveExtractionResult: Sendable {
    /// Extracted URLs by original item ID.
    public let urlsByItemID: [UUID: URL]

    public init(urlsByItemID: [UUID: URL]) {
        self.urlsByItemID = urlsByItemID
    }

    /// All extracted URLs.
    public var urls: [URL] {
        Array(urlsByItemID.values)
    }

    /// The single extracted URL.
    /// Fails if the result does not contain exactly one entry.
    public var singleURL: URL {
        get throws {
            guard urlsByItemID.count == 1, let url = urlsByItemID.values.first else {
                throw ArchiveError.extractionFailed(
                    "Expected exactly one extracted item, got \(urlsByItemID.count)"
                )
            }
            return url
        }
    }

    public subscript(item: ArchiveItem) -> URL? {
        urlsByItemID[item.id]
    }

    public subscript(id id: UUID) -> URL? {
        urlsByItemID[id]
    }
}

/// What testing an archive found.
public struct ArchiveTestResult: Equatable, Sendable {
    /// The entries that did not decode or did not match their checksum, by path.
    public let damagedEntries: [String]
    /// Whether the archive reports damage of its own: cut short, its headers
    /// broken. Every entry can read and the archive still not be whole.
    public let isArchiveDamaged: Bool

    public init(damagedEntries: [String], isArchiveDamaged: Bool) {
        self.damagedEntries = damagedEntries
        self.isArchiveDamaged = isArchiveDamaged
    }

    public var isIntact: Bool {
        damagedEntries.isEmpty && !isArchiveDamaged
    }
}

/// Byte-level progress reported by an engine during extraction. `completed`
/// and `total` share the engine's own processed-bytes unit. Return `false`
/// to abort the extraction. Called on the extraction thread.
public typealias ArchiveExtractionProgress = @Sendable (_ completed: Int64, _ total: Int64) -> Bool

/// An engine has the knowledge on how a library, CLI tool, or anything else
/// can extract certain formats. Examples would be the `XADMaster` library
/// that is included as an SPM package. Or the `7zip` CLI tool. An engine
/// is stateless and has no idea about UI or logic. It always takes a url to stay stateless.
public protocol ArchiveEngine: Sendable {
    
    /// Gives the status of the engine as a stream to the UI
    /// - Returns: status stream
    func statusStream() async -> AsyncStream<EngineStatus>
    
    /// Allows the UI to cancel the current action
    func cancel() async

    /// This engine, reading the names of an archive that does not declare their
    /// encoding in `encoding`, or working it out for `nil`. For the engines
    /// whose formats can leave it open.
    func readingNames(as encoding: ArchiveNameEncoding?) -> any ArchiveEngine

    /// Loads the given archive to retrieve all entries (in form of `ArchiveItem`)
    /// - Parameter url: url of the archive
    /// - Parameter passwordProvider: give the engine the possibility to request a password from the user
    /// - Returns: list of all entries
    func loadArchive(
        url: URL,
        passwordResolver: @escaping ArchivePasswordResolver
    ) async throws -> ArchiveEngineLoadResult
    
    /// Extracts the given item from the given archive to a temporary location
    /// - Parameters:
    ///   - item: item to extract
    ///   - from: archive url to extract the item from
    ///   - to: destination folder
    ///   - passwordProvider: give the engine the possibility to request a password from the user
    /// - Returns: the URL of the extracted item
    func extract(
        items: [ArchiveItem],
        from url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver
    ) async throws -> ArchiveExtractionResult
    
    func extract(
        item: ArchiveItem,
        from url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver
    ) async throws -> URL
    
    /// Extracts the full archive to the given destination
    /// - Parameters:
    ///   - url: url of the archive to be extracted
    ///   - destination: destination folder
    ///   - passwordProvider: give the engine the possibility to request a password from the user
    func extract(
        _ url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver
    ) async throws

    /// Extraction with engine byte progress. Engines that can't report
    /// progress use the default implementation, which ignores the callback.
    func extract(
        items: [ArchiveItem],
        from url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver,
        onProgress: ArchiveExtractionProgress?
    ) async throws -> ArchiveExtractionResult

    /// Full-archive extraction with engine byte progress. Engines that
    /// can't report progress use the default implementation, which ignores
    /// the callback.
    func extract(
        _ url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver,
        onProgress: ArchiveExtractionProgress?
    ) async throws

    /// Decodes every entry of the archive at `url` and checks it against its
    /// checksum, writing nothing. Asked only of an engine whose catalog entry
    /// declares `test`; the others keep the default implementation, which throws
    /// ``ArchiveError/testUnsupported``.
    func test(
        _ url: URL,
        passwordResolver: @escaping ArchivePasswordResolver,
        onProgress: ArchiveExtractionProgress?
    ) async throws -> ArchiveTestResult
}

public extension ArchiveEngine {
    func readingNames(as encoding: ArchiveNameEncoding?) -> any ArchiveEngine { self }

    // ponytail: 7-Zip only, the one engine the catalog declares `test` for.
    // XADMaster checks a checksum while it extracts, and its reads raise
    // exceptions Swift cannot catch, so testing there means extracting to a temp
    // folder; add it, and `test` to its catalog entries, if StuffIt users ask.
    func test(
        _ url: URL,
        passwordResolver: @escaping ArchivePasswordResolver,
        onProgress: ArchiveExtractionProgress?
    ) async throws -> ArchiveTestResult {
        throw ArchiveError.testUnsupported
    }

    func extract(
        items: [ArchiveItem],
        from url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver,
        onProgress: ArchiveExtractionProgress?
    ) async throws -> ArchiveExtractionResult {
        try await extract(items: items, from: url, to: destination, passwordResolver: passwordResolver)
    }

    func extract(
        _ url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver,
        onProgress: ArchiveExtractionProgress?
    ) async throws {
        try await extract(url, to: destination, passwordResolver: passwordResolver)
    }
}

public extension ArchiveEngine {
    func extract(
        item: ArchiveItem,
        from url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver
    ) async throws -> URL {
        let result = try await extract(
            items: [item],
            from: url,
            to: destination,
            passwordResolver: passwordResolver
        )

        return try result.singleURL
    }
}
