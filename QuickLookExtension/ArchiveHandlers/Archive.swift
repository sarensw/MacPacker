//
//  Archive.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 04.10.25.
//

import Foundation

struct Archive {
    let url: URL
    let hierarchy: ArchiveHierarchy?
    
    var rootNode: ArchiveItem { hierarchy?.root ?? .root }
}
