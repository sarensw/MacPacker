import Foundation
import Swift7zip
import Testing
@testable import Core

extension AllCoreTests {
    @MainActor struct GitIgnoreCompressionTests {
        private func fixture() throws -> (folder: URL, project: URL) {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let project = folder.appendingPathComponent("Project")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try "keep.txt\n".write(to: folder.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
            for path in ["node_modules", "build", "docs/deep", "nested", "other"] {
                try FileManager.default.createDirectory(
                    at: project.appendingPathComponent(path), withIntermediateDirectories: true)
            }
            let files: [String: String] = [
                ".gitignore": "node_modules/\n!node_modules/reinclude.js\nbuild/*\n!build/keep.txt\n/only-root.log\n*.tmp\n!important.tmp\ndocs/**/cache?.bin\n\\#literal\n",
                "keep.txt": "keep", "node_modules/pkg.js": "skip", "build/generated.o": "skip",
                "node_modules/reinclude.js": "still skip",
                "build/keep.txt": "keep", "only-root.log": "skip", "nested/only-root.log": "keep",
                "other/only-root.log": "keep",
                "scratch.tmp": "skip", "important.tmp": "keep", "nested/scratch.tmp": "skip",
                "docs/cache1.bin": "skip", "docs/deep/cache2.bin": "skip", "#literal": "skip",
                "nested/.gitignore": "*.log\n!important.log\n!only-root.log\n",
                "nested/debug.log": "skip", "nested/important.log": "keep",
            ]
            for (path, contents) in files {
                try contents.write(to: project.appendingPathComponent(path), atomically: true, encoding: .utf8)
            }
            return (folder, project)
        }

        @Test(arguments: CompressionOptions.Format.allCases)
        func ignoresNestedRulesAndPreservesExceptions(_ format: CompressionOptions.Format) async throws {
            let (folder, project) = try fixture()
            defer { try? FileManager.default.removeItem(at: folder) }
            let output = folder.appendingPathComponent("out.\(format.rawValue)")
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            await state.compress([project], to: output,
                                 options: .init(format: format, respectGitIgnore: true))
            #expect(state.error == nil, "\(state.error ?? "")")
            let paths = Set(try SevenZipArchive(url: output).entries.map(\.path))
            for path in ["Project/keep.txt", "Project/build/keep.txt", "Project/important.tmp",
                         "Project/nested/only-root.log", "Project/other/only-root.log",
                         "Project/nested/important.log",
                         "Project/.gitignore", "Project/nested/.gitignore"] {
                #expect(paths.contains(path), "\(path) should be kept")
            }
            for path in ["Project/node_modules/pkg.js", "Project/node_modules/reinclude.js",
                         "Project/build/generated.o",
                         "Project/only-root.log", "Project/scratch.tmp", "Project/nested/scratch.tmp",
                         "Project/docs/cache1.bin", "Project/docs/deep/cache2.bin",
                         "Project/#literal", "Project/nested/debug.log"] {
                #expect(!paths.contains(path), "\(path) should be ignored")
            }
        }

        @Test func compressContentsUsesTheContainingFoldersRules() async throws {
            let (folder, project) = try fixture()
            defer { try? FileManager.default.removeItem(at: folder) }
            let contents = try FileManager.default.contentsOfDirectory(at: project, includingPropertiesForKeys: nil)
            let output = folder.appendingPathComponent("contents.zip")
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            await state.compress(contents, to: output, options: .init(format: .zip, respectGitIgnore: true))
            #expect(state.error == nil, "\(state.error ?? "")")
            let paths = Set(try SevenZipArchive(url: output).entries.map(\.path))
            #expect(paths.contains("keep.txt"))
            #expect(paths.contains("build/keep.txt"))
            #expect(!paths.contains("node_modules/pkg.js"))
            #expect(!paths.contains("build/generated.o"))
            #expect(!paths.contains("Project/keep.txt"), "Compress Contents omits the enclosing folder")
        }

        @Test func offByDefaultAndDoesNotRemoveExistingEntries() async throws {
            let (folder, project) = try fixture()
            defer { try? FileManager.default.removeItem(at: folder) }
            let output = folder.appendingPathComponent("out.zip")
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            await state.compress([project], to: output, options: .init(format: .zip))
            #expect(state.error == nil)
            #expect(try SevenZipArchive(url: output).entries.contains { $0.path == "Project/node_modules/pkg.js" })

            let second = folder.appendingPathComponent("updated.zip")
            try SevenZipArchive.writeArchive(
                source: output, destination: second, items: [],
                options: .init(format: .zip, respectGitIgnore: true))
            #expect(try SevenZipArchive(url: second).entries.contains { $0.path == "Project/node_modules/pkg.js" })
        }

        @Test func preferenceAppliesAcrossSaveAndQuickCompress() throws {
            let suite = "gitignore-compression-\(UUID())"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let panel = ArchiveSaveOptions(defaults: defaults)
            #expect(!panel.respectGitIgnore)
            panel.respectGitIgnore = true
            #expect(!defaults.bool(forKey: Keys.respectGitIgnore), "Cancel must not change the global setting")
            panel.remember()
            let quick = ArchiveSaveOptions(defaults: defaults, storage: .quickCompress)
            #expect(quick.respectGitIgnore)
            #expect(try #require(quick.compressionOptions).respectGitIgnore)
            #expect(quick.startPageOptions.respectGitIgnore)
            quick.respectGitIgnore = false
            #expect(!defaults.bool(forKey: Keys.respectGitIgnore), "Quick Compress changes take effect immediately")
        }
    }
}
