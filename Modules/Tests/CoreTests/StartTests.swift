import Testing
import Foundation
@testable import Core

let defaultRoot = ArchiveItem(
    name: "root",
    type: .root
)

@MainActor struct StartTests {
    
    @Test func createArchiveState() async throws {
        await MainActor.run {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            #expect(state.error == nil)
        }
    }
    
//    func loadFiles() {
//        let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
//
//        let files = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
//        print(files)
//    }
    
    @Test func loadArchiveStateAndArchive() async throws {
        let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
        let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
        let url = folderURL.appendingPathComponent("defaultArchive.zip")
        
        state.open(url: url)
        try await state.openTask?.value
        
        #expect(state.type?.id == "zip")
        #expect(state.entries.count == 4)
        #expect(state.root?.children?.count == 2)
        #expect(state.root === state.selectedItem)
    }
    
    @Test func compareDefaultZip() async throws {
        let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
        let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
        let url = folderURL.appendingPathComponent("defaultArchive.zip")
        
        state.open(url: url)
        try await state.openTask?.value
        
        #expect(state.entries.count == 4)
        
        // level 0: root
        let level0a = state.root!.children!
        #expect(level0a.count == 2)
        #expect(level0a[0].name == "folder")
        #expect(level0a[0].type == .directory)
        #expect(level0a[1].name == "hello world.txt")
        #expect(level0a[1].type == .file)
        
        // level 0: selectedItem
        let level0b = state.selectedItem!.children!
        #expect(level0b.count == 2)
        #expect(level0b[0].name == "folder")
        #expect(level0b[0].type == .directory)
        #expect(level0b[1].name == "hello world.txt")
        #expect(level0b[1].type == .file)
        
        // level 1
        try await state.openAsync(item: level0b[0])
        let level1 = state.selectedItem!.children!.sorted { item1, item2 in
            item1.name < item2.name
        }
        #expect(level1.count == 2)
        #expect(level1[0].name == "NestedArchive.zip")
        #expect(level1[0].type == .file)
        #expect(level1[1].name == "README.md")
        #expect(level1[1].type == .file)
        
        // level 2
        try await state.openAsync(item: level1[0])
        let level2 = state.selectedItem!.children!.sorted { item1, item2 in
            item1.name < item2.name
        }
        #expect(level2.count == 3)
        #expect(level2[0].name == "keynote.pdf")
        #expect(level2[0].type == .file)
        #expect(level2[1].name == "photo.psd")
        #expect(level2[1].type == .file)
        #expect(level2[2].name == "taxes.xlsx")
        #expect(level2[2].type == .file)
    }
}
