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
        let expanded = expandDirectories(items: items, entries: entries)

        let utilities = ArchiveSupportUtilities()
        var resultEngine: [URL: ArchiveEngineType] = [:]
        var resultItems: [URL: [ArchiveItem]] = [:]

        for item in expanded {
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

    /// Expands directory items to include all their descendants so that
    /// engines that extract by index get the full subtree.
    private func expandDirectories(
        items: [ArchiveItem],
        entries: [UUID: ArchiveItem]
    ) -> [ArchiveItem] {
        var result: [ArchiveItem] = []
        var seen: Set<UUID> = []

        func collect(_ item: ArchiveItem) {
            guard seen.insert(item.id).inserted else { return }
            result.append(item)
            if let childIDs = item.children {
                for childID in childIDs {
                    if let child = entries[childID] {
                        collect(child)
                    }
                }
            }
        }

        for item in items {
            collect(item)
        }
        return result
    }
}
