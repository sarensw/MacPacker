//
//  SystemHelper.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 28.07.25.
//

import AppKit

final class SystemHelper {
    public static let shared = SystemHelper()
    
    private init() {}
    
    func getNSImageByExtension(fileName: String) -> NSImage? {
        let fileExtension = (fileName as NSString).pathExtension
        let icon = NSWorkspace.shared.icon(forFileType: fileExtension)
        return icon
    }
    
    func getNSImageForFolder() -> NSImage {
        return NSWorkspace.shared.icon(for: .folder)
    }
}

