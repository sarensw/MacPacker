//
//  Archive7ZipEngine.swift
//  Modules
//
//  Created by Stephan Arenswald on 30.11.25.
//

import Foundation
import Subprocess
import System

public final class Archive7ZipEngine: ArchiveEngine {
    public func loadArchive(url: URL) async throws -> [ArchiveItem] {
        guard let cmdUrl = Bundle.main.url(forResource: "7zz", withExtension: nil) else {
            print("Failed to load 7zz exec")
            throw ArchiveError.loadFailed("Failed to load 7zz exec")
        }
        let path = FilePath(cmdUrl.path)
        var items: [ArchiveItem] = []
        
        let _ = try await Subprocess.run(
            .path(path),
            arguments: ["l", url.path]
        ) { execution, standardOutput in
            var inBlock: Bool = false
            for try await line in standardOutput.lines() {
                if line.starts(with: "-------------------") {
                    inBlock.toggle()
                } else if inBlock {
                    if let item = parse7zListLineFast(line.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        items.append(item)
                    }
                }
            }
        }
        
        return items
    }
    
    public func extract(item: ArchiveItem, from url: URL, to destination: URL) async throws -> URL? {
        guard let cmdUrl = Bundle.main.url(forResource: "7zz", withExtension: nil) else {
            Logger.error("Failed to load 7zz exec")
            throw ArchiveError.loadFailed("Failed to load 7zz exec")
        }
        guard let virtualPath = item.virtualPath else {
            Logger.error("No virtual path for item")
            return nil
        }
        let path = FilePath(cmdUrl.path)
        
        let args = [
            "e",
            url.path,
            "\(virtualPath)",
            "-o\(destination.path)",
            "-spf"
        ]
        
        Logger.log("""
            \(cmdUrl.path)
                \(args.reduce("", { $0 + $1 + "\n\t" }))
        """)
        
        let _ = try await Subprocess.run(
            .path(path),
            arguments: Arguments(args)
        ) { execution, standardOutput in
            var cnt = 0
            for try await line in standardOutput.lines() {
                cnt += 1
                print(line.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            print("\(cnt) items found")
        }
        
        let resultUrl = destination.appendingPathComponent(virtualPath)
        return resultUrl
    }
    
    public func extract(_ url: URL, to destination: URL) async throws {
        let cmdPath = try getCommandFilePath()
        
        let args = [
            "e",
            url.path,
            "-o\(destination.path)",
            "-spf"
        ]
        
        Logger.log("""
            \(cmdPath)
                \(args.reduce("", { $0 + $1 + "\n\t" }))
        """)
        
        let _ = try await Subprocess.run(
            .path(cmdPath),
            arguments: Arguments(args)
        ) { execution, standardOutput in
            var cnt = 0
            for try await line in standardOutput.lines() {
                cnt += 1
                print(line.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            print("\(cnt) items found")
        }
    }
    
    private func getCommandFilePath() throws -> FilePath {
        guard let cmdUrl = Bundle.main.url(forResource: "7zz", withExtension: nil) else {
            Logger.error("Failed to load 7zz exec")
            throw ArchiveError.loadFailed("Failed to load 7zz exec")
        }
        return FilePath(cmdUrl.path)
    }
    
    private func parse7zListLineFast(_ line: String) -> ArchiveItem? {
        // Skip non-entry lines quickly (e.g. summary/footer)
        guard let first = line.first, first.isNumber else { return nil }
        
        // 7z `l` layout (approx):
        // date(10) space time(8) space attrs(5) space size space compressed space path
        //          012345678901234567890123456789012345678901234567890123456789
        //          0         1         2         3         4         5
        // Example:
        // 2025-11-04 12:46:30 ..HS.    309592064    309592064  [SYSTEM]/$MFT
        
        guard line.count > 53 else { return nil }
        
        let s = line
        let start = s.startIndex
        
        // attrs at ~20–25
        let attrStart = s.index(start, offsetBy: 20)
        let attrEnd   = s.index(attrStart, offsetBy: 5, limitedBy: s.endIndex) ?? s.endIndex
        let attrs     = s[attrStart..<attrEnd]
        let isDir = attrs.contains("D")
        
        // path at ~53+, skip leading spaces
        let pathStart = s.index(start, offsetBy: 53, limitedBy: s.endIndex) ?? s.endIndex
        let pathSub = s[pathStart...].drop(while: { $0 == " " })
        
        guard !pathSub.isEmpty else { return nil }
        let path = String(pathSub)
        
        // name = last path component
        let name: String
        if let idx = path.lastIndex(of: "/") {
            name = String(path[path.index(after: idx)...])
        } else {
            name = path
        }
        
        return ArchiveItem(
            name: name,
            virtualPath: path,
            type: isDir ? .directory : .file
        )
    }
}
