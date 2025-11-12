//
//  ArchiveCapability.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 01.11.25.
//

/// List of possible capabilities a handler supports on a given archive
public enum ArchiveCapability: Hashable {
    
    /// List content / preview content of an archive
    case view
    
    /// Extract single files from or the full archive
    case extract
    
    /// Create that archive
    case create
    
    /// Update that archive (add / remove / rename)
    case update
}
