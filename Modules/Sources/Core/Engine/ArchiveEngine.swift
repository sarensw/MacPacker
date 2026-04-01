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
    case cancelled
    case idle
    case processing(progress: Double?, message: String)
    case done
    case error(Error)
}

public struct ArchiveEngineLoadResult: Sendable {
    let items: [UUID: ArchiveItem]
    let hasTree: Bool
    let uncompressedSize: Int64
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
