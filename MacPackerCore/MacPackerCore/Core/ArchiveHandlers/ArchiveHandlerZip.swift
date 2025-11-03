//
//  ArchiveHandlerZip.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 05.09.25.
//

//import Foundation
//import SWCompression
//import XADMaster
//import ZIPFoundation
//
//typealias ZipArchive = ZIPFoundation.Archive
//
//class ArchiveHandlerZip: ArchiveHandlerXad {
//    static func registerZip() {
//        let registry = ArchiveHandlerRegistry.shared
//        let handler = ArchiveHandlerZip()
//        
//        // TODO: zip variants are hard coded now. Make them generic
//        registry.register(ext: "zip", handler: handler)
//        registry.register(ext: "xlsx", handler: handler)
//        registry.register(ext: "docx", handler: handler)
//        registry.register(ext: "pptx", handler: handler)
//    }
//    
//    override var isEditable: Bool { true }
//    
//    override func save(to url: URL, items: [ArchiveItem]) throws {
//        let fileExists = FileManager.default.fileExists(atPath: url.path)
//        let archive = try ZipArchive(
//            url: url,
//            accessMode: fileExists ? .update : .create)
//        
//        for item in items {
//            if let path = item.path {
//                try archive.addEntry(
//                    with: path.lastPathComponent,
//                    relativeTo: path.deletingLastPathComponent())
//            }
//        }
//    }
//}
