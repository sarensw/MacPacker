//
//  ZipTests.swift
//  Modules
//
//  Created by Stephan Arenswald on 11.12.25.
//

import Testing
import Foundation
@testable import Core

extension AllCoreTests {
    @MainActor struct ZipTests {
        
        @Test func nestedFolders7Zip() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let folderURL = Bundle.module.url(forResource: "zip", withExtension: nil)!
            let url = folderURL.appendingPathComponent("nestedFolders.zip")
            
            state.open(url: url)
            try await state.openTask?.value
            
            #expect(state.root != nil)
            
            let first = state.entries[state.root!.children!.first!]!
            let extractedUrl = try await state.extractToTemp(item: first)
            print(String(describing: extractedUrl))
            
            #expect(FileManager.default.fileExists(atPath: extractedUrl.path))
            
            // level 1
            #expect(FileManager.default.fileExists(atPath: extractedUrl.appendingPathComponent("level1").path))
            #expect(FileManager.default.fileExists(atPath: extractedUrl.appendingPathComponent("level2").path))
            
            // level 2
            #expect(FileManager.default.fileExists(atPath: extractedUrl.appendingPathComponent("level2").appendingPathComponent("level2").path))
            #expect(FileManager.default.fileExists(atPath: extractedUrl.appendingPathComponent("level2").appendingPathComponent("level3").path))
            
            // level 3
            #expect(FileManager.default.fileExists(atPath: extractedUrl.appendingPathComponent("level2").appendingPathComponent("level3").appendingPathComponent("level3").path))
            #expect(FileManager.default.fileExists(atPath: extractedUrl.appendingPathComponent("level2").appendingPathComponent("level3").appendingPathComponent("level4").path))
            
            // level 4
            #expect(FileManager.default.fileExists(atPath: extractedUrl.appendingPathComponent("level2").appendingPathComponent("level3").appendingPathComponent("level4").appendingPathComponent("level4").path))
        }
        
        @Test func nestedFoldersXad() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelectorXad())
            let folderURL = Bundle.module.url(forResource: "zip", withExtension: nil)!
            let url = folderURL.appendingPathComponent("nestedFolders.zip")
            
            state.open(url: url)
            try await state.openTask?.value
            
            #expect(state.root != nil)
            
            let first = state.entries[state.root!.children!.first!]!
            let extractedUrl = try await state.extractToTemp(item: first)
            print(String(describing: extractedUrl))
            
            #expect(FileManager.default.fileExists(atPath: extractedUrl.path))
            
            // level 1
            #expect(FileManager.default.fileExists(atPath: extractedUrl.appendingPathComponent("level1").path))
            #expect(FileManager.default.fileExists(atPath: extractedUrl.appendingPathComponent("level2").path))
            
            // level 2
            #expect(FileManager.default.fileExists(atPath: extractedUrl.appendingPathComponent("level2").appendingPathComponent("level2").path))
            #expect(FileManager.default.fileExists(atPath: extractedUrl.appendingPathComponent("level2").appendingPathComponent("level3").path))
            
            // level 3
            #expect(FileManager.default.fileExists(atPath: extractedUrl.appendingPathComponent("level2").appendingPathComponent("level3").appendingPathComponent("level3").path))
            #expect(FileManager.default.fileExists(atPath: extractedUrl.appendingPathComponent("level2").appendingPathComponent("level3").appendingPathComponent("level4").path))
            
            // level 4
            #expect(FileManager.default.fileExists(atPath: extractedUrl.appendingPathComponent("level2").appendingPathComponent("level3").appendingPathComponent("level4").appendingPathComponent("level4").path))
        }

        /// Zips written without directory entries (`zip -D`, and what several
        /// download sites serve) only list `folder/file.txt`. The folder itself
        /// is synthesized by `ArchiveLoader.buildTree`, so it must still show up.
        @Test func zipWithoutDirectoryEntries() async throws {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("ZipTests-\(UUID().uuidString)")
            let src = dir.appendingPathComponent("folder")
            try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            try "hello".write(to: src.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

            // -D: no directory entries, so the archive holds a single entry
            // "folder/file.txt" and nothing else.
            let zip = dir.appendingPathComponent("noDirEntries.zip")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            p.arguments = ["-D", "-r", zip.path, "folder"]
            p.currentDirectoryURL = dir
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run()
            p.waitUntilExit()
            #expect(p.terminationStatus == 0)

            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.open(url: zip)
            try await state.openTask?.value

            #expect(state.childItems?.count == 1)
            let folder = try #require(state.childItems?.first)
            #expect(folder.name == "folder")
            #expect(folder.isFolder)

            try await state.openAsync(item: folder)
            #expect(state.childItems?.map(\.name) == ["file.txt"])
        }
    }
}
