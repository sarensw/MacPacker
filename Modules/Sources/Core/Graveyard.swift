////
////  Graveyard.swift
////  Modules
////
////  Created by Stephan Arenswald on 25.11.25.
////
//
//
//
//private func getHandler(type: ArchiveHandlerType) -> ArchiveHandler {
//    switch type {
//    case .xad: return xad
//    case .`7zip`: return szip
//    default: return szip
//    }
//}
//
//private func findHandlerAndUrl(for archiveItem: ArchiveItem) -> (ArchiveHandler?, URL?) {
//    var item: ArchiveItem? = archiveItem
//    var url: URL?
//    var handler: ArchiveHandler?
//    
//    while item != nil {
//        if item?.handlerType != nil && item?.url != nil {
//            url = item?.url
//            handler = getHandler(type: item!.handlerType!)
//            break
//        }
//        item = item?.parent
//    }
//    
//    return (handler, url)
//}
