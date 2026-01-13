//
//  ZipTests.swift
//  Modules
//
//  Created by Stephan Arenswald on 11.12.25.
//

import Testing
import Foundation
@testable import Core



@MainActor struct ZipTests {
    
    @Test func nestedFolders7Zip() async throws {
        let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
        let folderURL = Bundle.module.url(forResource: "zip", withExtension: nil)!
        let url = folderURL.appendingPathComponent("nestedFolders.zip")
        
        state.open(url: url)
        try await state.openTask?.value
        
        #expect(state.root != nil)
        
        let extractedUrl = try await state.extractAsync(item: state.root!.children!.first!)
        print(String(describing: extractedUrl))
        
        #expect(extractedUrl != nil)
        #expect(FileManager.default.fileExists(atPath: extractedUrl!.path))
        
        // level 1
        #expect(FileManager.default.fileExists(atPath: extractedUrl!.appendingPathComponent("level1").path))
        #expect(FileManager.default.fileExists(atPath: extractedUrl!.appendingPathComponent("level2").path))
        
        // level 2
        #expect(FileManager.default.fileExists(atPath: extractedUrl!.appendingPathComponent("level2").appendingPathComponent("level2").path))
        #expect(FileManager.default.fileExists(atPath: extractedUrl!.appendingPathComponent("level2").appendingPathComponent("level3").path))
        
        // level 3
        #expect(FileManager.default.fileExists(atPath: extractedUrl!.appendingPathComponent("level2").appendingPathComponent("level3").appendingPathComponent("level3").path))
        #expect(FileManager.default.fileExists(atPath: extractedUrl!.appendingPathComponent("level2").appendingPathComponent("level3").appendingPathComponent("level4").path))
        
        // level 4
        #expect(FileManager.default.fileExists(atPath: extractedUrl!.appendingPathComponent("level2").appendingPathComponent("level3").appendingPathComponent("level4").appendingPathComponent("level4").path))
    }
    
    @Test func nestedFoldersXad() async throws {
        let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelectorXad())
        let folderURL = Bundle.module.url(forResource: "zip", withExtension: nil)!
        let url = folderURL.appendingPathComponent("nestedFolders.zip")
        
        state.open(url: url)
        try await state.openTask?.value
        
        #expect(state.root != nil)
        
        let extractedUrl = try await state.extractAsync(item: state.root!.children!.first!)
        print(String(describing: extractedUrl))
        
        #expect(extractedUrl != nil)
        #expect(FileManager.default.fileExists(atPath: extractedUrl!.path))
        
        // level 1
        #expect(FileManager.default.fileExists(atPath: extractedUrl!.appendingPathComponent("level1").path))
        #expect(FileManager.default.fileExists(atPath: extractedUrl!.appendingPathComponent("level2").path))
        
        // level 2
        #expect(FileManager.default.fileExists(atPath: extractedUrl!.appendingPathComponent("level2").appendingPathComponent("level2").path))
        #expect(FileManager.default.fileExists(atPath: extractedUrl!.appendingPathComponent("level2").appendingPathComponent("level3").path))
        
        // level 3
        #expect(FileManager.default.fileExists(atPath: extractedUrl!.appendingPathComponent("level2").appendingPathComponent("level3").appendingPathComponent("level3").path))
        #expect(FileManager.default.fileExists(atPath: extractedUrl!.appendingPathComponent("level2").appendingPathComponent("level3").appendingPathComponent("level4").path))
        
        // level 4
        #expect(FileManager.default.fileExists(atPath: extractedUrl!.appendingPathComponent("level2").appendingPathComponent("level3").appendingPathComponent("level4").appendingPathComponent("level4").path))
    }
}
