////
////  ArchiveHandlerP7ZipSubProcess.swift
////  MacPackerCore
////
////  Created by Stephan Arenswald on 17.11.25.
////
//
//import Foundation
//import Subprocess
//import System
//
//public actor ArchiveHandlerP7ZipSubProcess: ArchiveListing, ArchiveExtracting {
//    public func contents(of url: URL) throws -> [ArchiveItem] {
//        <#code#>
//    }
//    
//    public func content(archiveUrl: URL, archivePath: String) throws -> [ArchiveItem] {
//        <#code#>
//    }
//    
//    public func extractToTemp(path: URL) -> URL? {
//        <#code#>
//    }
//    
//    public func extractFileToTemp(path: URL, item: ArchiveItem) -> URL? {
//        <#code#>
//    }
//    
//    public func extract(archiveUrl: URL, archiveItem: ArchiveItem, to url: URL) {
//        <#code#>
//    }
//    
//    public func extract(archiveUrl: URL, to url: URL) {
//        <#code#>
//    }
//    
//    public static func register() {
//        let handler = ArchiveHandlerP7ZipSubProcess()
//        
//        let typeRegistry = ArchiveTypeRegistry.shared
//        
//        typeRegistry.register(typeID: .vhdx, capabilities: [.view, .extract], handler: handler)
//        typeRegistry.register(typeID: .ntfs, capabilities: [.view, .extract], handler: handler)
//    }
//    
//    private func binaryURL() throws -> URL {
//        guard let url = Bundle.main.url(forResource: "7zz", withExtension: nil) else {
//            print("Failed to load 7zz exec")
//            throw ArchiveError.loadFailed("Failed to load 7zz exec")
//        }
//        return url
//    }
//    
//    public func contents(
//        of url: URL
//    ) async throws -> [ArchiveItem] {
//        guard let cmdUrl = Bundle.main.url(forResource: "7zz", withExtension: nil) else {
//            print("Failed to load 7zz exec")
//            throw ArchiveError.loadFailed("Failed to load 7zz exec")
//        }
//        let path = FilePath(cmdUrl.path)
//        var items: [ArchiveItem] = []
//        
//        Date.now.printNowWithMs("1")
//        
//        let _ = try await Subprocess.run(
//            .path(path),
//            arguments: ["l", url.path]
//        ) { execution, standardOutput in
//            var cnt = 0
//            for try await line in standardOutput.lines() {
//                cnt += 1
//                if cnt >= 0 && cnt <= 100 {
//                    if let item = parse7zListLineFast(line.trimmingCharacters(in: .whitespacesAndNewlines)) {
//                        items.append(item)
//                    }
//                }
//            }
//            Date.now.printNowWithMs("2")
//            print("\(cnt) items found")
//        }
//        
//        return []
//    }
//    
//    private func parse7zListLineFast(_ line: String) -> ArchiveItem? {
//        // Skip non-entry lines quickly (e.g. summary/footer)
//        guard let first = line.first, first.isNumber else { return nil }
//
//        // 7z `l` layout (approx):
//        // date(10) space time(8) space attrs(5) space size space compressed space path
//        //          012345678901234567890123456789012345678901234567890123456789
//        //          0         1         2         3         4         5
//        // Example:
//        // 2025-11-04 12:46:30 ..HS.    309592064    309592064  [SYSTEM]/$MFT
//
//        guard line.count > 53 else { return nil }
//
//        let s = line
//        let start = s.startIndex
//
//        // attrs at ~20–25
//        let attrStart = s.index(start, offsetBy: 20)
//        let attrEnd   = s.index(attrStart, offsetBy: 5, limitedBy: s.endIndex) ?? s.endIndex
//        let attrs     = s[attrStart..<attrEnd]
//        let isDir = attrs.contains("D")
//
//        // path at ~53+, skip leading spaces
//        let pathStart = s.index(start, offsetBy: 53, limitedBy: s.endIndex) ?? s.endIndex
//        let pathSub = s[pathStart...].drop(while: { $0 == " " })
//
//        guard !pathSub.isEmpty else { return nil }
//        let path = String(pathSub)
//
//        // name = last path component
//        let name: String
//        if let idx = path.lastIndex(of: "/") {
//            name = String(path[path.index(after: idx)...])
//        } else {
//            name = path
//        }
//
//        return ArchiveItem(
//            name: name,
//            virtualPath: path,
//            type: isDir ? .directory : .file
//        )
//    }
//}
