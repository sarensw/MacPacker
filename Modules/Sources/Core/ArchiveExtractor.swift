//
//  ArchiveExtractor.swift
//  Modules
//
//  Created by Stephan Arenswald on 24.12.25.
//

import Foundation

struct ArchiveExtractorResult {
    /// The url of the file or directory that was extracted
    let url: URL
    
    /// The url of the temporary directory created to store and
    /// later move or copy the file from to the destination
    let tempDirectory: URL
}

final actor ArchiveExtractor {
    private let archiveEngineSelector: ArchiveEngineSelectorProtocol
    
    init(archiveEngineSelector: ArchiveEngineSelectorProtocol) {
        self.archiveEngineSelector = archiveEngineSelector
    }
    
    /// This will extract the given item from the archive to a temporary destination
    /// - Parameter archiveItem: item to extract
    /// - Returns: the url of the extracted file when successful
    public func extractAsync(item: ArchiveItem) async throws -> ArchiveExtractorResult? {
        // We need to figure out first which archive actually contains
        // the currently selected file. Is it the root archive, or is
        // it a nested archive?
        
        let archiveSupportUtilities = ArchiveSupportUtilities()
        
        guard let temp = archiveSupportUtilities.createTempDirectory() else {
            Logger.error("Could not create temp directory for extraction")
            return nil
        }
        
        if let (archiveTypeId, archiveUrl) = archiveSupportUtilities.findHandlerAndUrl(for: item),
           let engine = archiveEngineSelector.engine(for: archiveTypeId) {
            
            guard let url = try await engine.extract(
                item: item,
                from: archiveUrl,
                to: temp.url
            ) else {
                return nil
            }
            
            return ArchiveExtractorResult(url: url, tempDirectory: temp.url)
        }
        
        return nil
    }
}
