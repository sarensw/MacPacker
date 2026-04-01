//
//  ArchiveExtractor.swift
//  Modules
//
//  Created by Stephan Arenswald on 24.12.25.
//

import Foundation

struct SingleExtractionResult {
    let url: URL
    let tempDir: URL
}

struct MultiExtractionResult {
    let urls: [UUID: URL]
    let tempDirs: [URL]
}

final actor ArchiveExtractor {
    private let archiveEngineSelector: ArchiveEngineSelectorProtocol
    private let passwordResolver: ArchivePasswordResolver

    init(
        archiveEngineSelector: ArchiveEngineSelectorProtocol,
        passwordResolver: @escaping ArchivePasswordResolver
    ) {
        self.archiveEngineSelector = archiveEngineSelector
        self.passwordResolver = passwordResolver
    }

    /// Moves the given set of extracted temporary files to another destination.
    ///
    /// This is usually used to move extracted file(s) from their temporary location
    /// to the final target directory.
    ///
    /// - Parameters:
    ///   - extractedURLs: The extracted item urls keyed by item id.
    ///   - destination: The target directory.
    ///   - items: List of items relevant for being moved.
    private func moveExtractedItems(
        _ extractedURLs: [UUID: URL],
        to destination: URL,
        items: [ArchiveItem]
    ) throws {
        _ = destination.startAccessingSecurityScopedResource()
        defer { destination.stopAccessingSecurityScopedResource() }
        
        let itemsById = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        // Finally, move the file from the temp location to the actual destination.
        for (id, sourceURL) in extractedURLs {
            guard let item = itemsById[id] else { continue }

            let targetURL = destination.appending(component: item.name)
            try FileManager.default.moveItem(at: sourceURL, to: targetURL)
        }
    }

    /// Extracts a single batch into a newly created temp directory.
    ///
    /// - Parameter batch: The batch to extract.
    /// - Returns: The extracted urls keyed by item id and the temp directory used for extraction.
    private func extract(
        batch: ResolvedBatch
    ) async throws -> ([UUID: URL], URL) {
        let utilities = ArchiveSupportUtilities()

        guard let temp = utilities.createTempDirectory() else {
            throw ArchiveError.extractionFailed("Could not create temp directory")
        }

        let engine = archiveEngineSelector.engine(for: batch.engineType)

        let extractedURLs = try await engine.extract(
            items: batch.items,
            from: batch.archiveURL,
            to: temp.url,
            passwordResolver: passwordResolver
        )

        return (extractedURLs.urlsByItemID, temp.url)
    }

    /// Extracts a single item from a resolved batch to the target directory through a temp directory.
    ///
    /// The item is extracted to a temp directory first, then moved to the target.
    /// This avoids sandboxing issues when extracting directly to a user-chosen destination.
    ///
    /// - Parameters:
    ///   - batch: A resolved batch containing the item, its archive URL, and engine type.
    ///   - destination: Destination folder. If `nil`, the extracted file stays in temp.
    /// - Returns: The extracted file URL and the temp directory used.
    public func extract(
        batch: ResolvedBatch,
        to destination: URL? = nil
    ) async throws -> SingleExtractionResult {
        guard let item = batch.items.first else {
            throw ArchiveError.extractionFailed("Cannot extract: no items provided")
        }
        let (extractedURLs, tempDirectory) = try await extract(batch: batch)

        // For single-item extraction, we expect exactly one extracted result.
        guard let extractedURL = extractedURLs[item.id] ?? extractedURLs.values.first else {
            throw ArchiveError.extractionFailed("Extraction of item failed, but no url was returned")
        }

        // Only if there is a target directory then we move the file there,
        // otherwise we keep it in the temp spot.
        if let destination {
            try moveExtractedItems(extractedURLs, to: destination, items: [item])
        }

        return SingleExtractionResult(
            url: extractedURL,
            tempDir: tempDirectory
        )
    }

    /// Extracts items from multiple resolved batches to the target directory through temp directories.
    ///
    /// Each batch is extracted to its own temp directory, then moved to the target.
    /// This avoids sandboxing issues when extracting directly to a user-chosen destination.
    ///
    /// - Parameters:
    ///   - batches: Resolved batches, each containing items grouped by archive URL and engine type.
    ///   - destination: Destination folder. If `nil`, extracted files stay in temp.
    /// - Returns: All extracted file URLs keyed by item ID, and the temp directories used.
    public func extract(
        batches: [ResolvedBatch],
        to destination: URL? = nil
    ) async throws -> MultiExtractionResult {
        var allExtractedURLs: [UUID: URL] = [:]
        var tempDirectories: [URL] = []

        for batch in batches {
            let (extractedURLs, tempDirectory) = try await extract(batch: batch)

            tempDirectories.append(tempDirectory)
            allExtractedURLs.merge(extractedURLs) { current, _ in current }

            // Only if there is a target directory then we move the files there,
            // otherwise we keep them in the temp spot.
            if let destination {
                try moveExtractedItems(extractedURLs, to: destination, items: batch.items)
            }
        }

        return MultiExtractionResult(
            urls: allExtractedURLs,
            tempDirs: tempDirectories
        )
    }
    
    /// Extracts the given archive fully
    /// - Parameters:
    ///   - url: archive to extract
    ///   - archiveEngineType: type of engine
    ///   - destination: destination directory
    public func extractAll(
        _ url: URL,
        archiveTypeId: String,
        to destination: URL
    ) async throws {
        _ = destination.startAccessingSecurityScopedResource()
        defer { destination.stopAccessingSecurityScopedResource() }
        
        guard let engine = archiveEngineSelector.engine(for: archiveTypeId) else {
            throw ArchiveError.extractionFailed("Could not determine archive engine for \(archiveTypeId).")
        }

        try await engine.extract(url, to: destination, passwordResolver: passwordResolver)
    }
}
