//
//  ArchiveContentService.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 08.09.25.
//

import AppKit
import Foundation

class ArchiveContentService {
    
    /// Opens the systems default info window for the current archive
    /// - Parameter urls: url of the archive to open the info window with
    func openGetInfoWnd(for urls: [URL]) {
        let pBoard = NSPasteboard(name: NSPasteboard.Name(rawValue: "pasteBoard_\(UUID().uuidString )") )
        
        pBoard.writeObjects(urls as [NSPasteboardWriting])
        
        NSPerformService("Finder/Show Info", pBoard)
    }
}
