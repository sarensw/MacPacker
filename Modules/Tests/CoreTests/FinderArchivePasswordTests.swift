import Foundation
import Swift7zip
import Testing
@testable import Core

extension AllCoreTests {
    @MainActor struct FinderArchivePasswordTests {
        @Test func generatedPasswordEncryptsAnArchiveAndItsFileNames() async throws {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let source = folder.appendingPathComponent("secret.txt")
            try "private".write(to: source, atomically: true, encoding: .utf8)
            let archive = folder.appendingPathComponent("secret.7z")
            let password = try FinderArchivePassword.generate()
            let second = try FinderArchivePassword.generate()
            #expect(password.count == 24)
            #expect(password != second)
            #expect(password.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0)
                || (48...57).contains($0) || $0 == 45 || $0 == 95 })

            let options = FinderArchivePassword.compressionOptions(password: password)
            #expect(options.format == .sevenZ)
            #expect(options.encryptFileNames)
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            await state.compress([source], to: archive, options: options)
            #expect(state.error == nil, "\(state.error ?? "")")
            #expect(throws: (any Error).self) {
                try SevenZipArchive(url: archive)
            }
            let reader = try SevenZipArchive(url: archive, password: password)
            let entries = try reader.entries
            #expect(entries.contains { $0.path == "secret.txt" })
        }
    }
}
