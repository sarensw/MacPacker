//
//  ArchiveBatchResolver.swift
//  Modules
//
//  Created by Stephan Arenswald on 29.03.26.
//

import Foundation

// A group of items that share the same archive source and engine. This is
// relevant due to the support of nested archives. It allows a user to
// select two items in the archive tree where one item is from the actual archive
// and the other from a nested archive
public struct ResolvedBatch: Sendable {
    let archiveURL: URL
    let engineType: ArchiveEngineType
    let items: [ArchiveItem]
}

final class ArchiveBatchResolver {
    // Resolves which archive and engine each item belongs to, groups them
    // into batches for efficient multi-index extraction.
    // Lives in ArchiveSupportUtilities or a dedicated BatchResolver.
    func resolveBatches(
        for items: [ArchiveItem],
        in entries: [UUID: ArchiveItem],
        using selector: ArchiveEngineSelectorProtocol
    ) throws -> [ResolvedBatch] {
        let utilities = ArchiveSupportUtilities()
        var resultEngine: [URL: ArchiveEngineType] = [:]
        var resultItems: [URL: [ArchiveItem]] = [:]
        
        for item in items {
            guard
                let (archiveTypeID, archiveURL) = utilities.findHandlerAndUrl(for: item, in: entries),
                let engineType = selector.engineType(for: archiveTypeID)
            else {
                throw ArchiveError.extractionFailed("Could not determine engine for extraction")
            }
            
            resultEngine[archiveURL] = engineType
            resultItems[archiveURL, default: []].append(item)
        }
        
        return resultItems.map({
            ResolvedBatch(
                archiveURL: $0.key,
                engineType: resultEngine[$0.key]!,
                items: $0.value
            )
        })
    }
}
