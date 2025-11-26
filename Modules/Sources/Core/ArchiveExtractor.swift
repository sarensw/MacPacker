////
////  ArchiveExtractor.swift
////  Modules
////
////  Created by Stephan Arenswald on 23.11.25.
////
//
//import Foundation
//
//actor ArchiveExtractor {
//    private let xad = ArchiveHandlerXad()
//    private let szip = ArchiveHandlerP7ZipSubProcess()
//    
//    private let catalog = ArchiveTypeCatalog.shared
//    private let detector = ArchiveTypeDetector()
//    
//    private func getHandler(type: ArchiveHandlerType) -> ArchiveHandler {
//        switch type {
//        case .xad: return xad
//        case .`7zip`: return szip
//        default: return szip
//        }
//    }
//    
//    func extract(from archive: Archive, item: ArchiveItem, to destination: URL) async throws {
//        if let handlerType = catalog.selectedHandlerByID[archive.type.id] {
//            let handler = getHandler(type: handlerType)
//            
//            handler.extract(archiveUrl: archive.url, to: destination)
//        }
//    }
//    
//    func extract(_ archive: Archive, to: URL) async throws {
//        
//    }
//    
//    func extractToTemp(archiveItem: ArchiveItem, using handler: ArchiveHandler) async throws -> URL {
//        
//    }
//    
//    
//    public func extract(archiveItem: ArchiveItem) -> URL? {
//        // We need to figure out first which archive actually contains
//        // the currently selected file. Is it the root archive, or is
//        // it a nested archive?
//        
//        let (handler, archiveUrl) = findHandlerAndUrl(for: archiveItem)
//        if let handler, let archiveUrl {
//            let url = handler.extractFileToTemp(path: archiveUrl, item: archiveItem)
//            return url
//        }
//        
//        return nil
//    }
//}
