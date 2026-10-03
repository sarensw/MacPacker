import Foundation
import Testing
import Swift7zip
import CSevenZip
import FinderMenu
@testable import Core

extension AllCoreTests {
    struct ReviewSafetyTests {
        @Test func cleanupDetectsChangesWithPreservedMetadata() throws {
            let root = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            let source = root.appendingPathComponent("source.rar")
            try FileManager.default.copyItem(at: Bundle.module.resourceURL!.appendingPathComponent("defaultArchives/defaultArchive.rar"), to: source)
            let cleanup = try ExtractionSourceCleanup(source: source, catalog: ArchiveTypeCatalog())
            let attrs = try FileManager.default.attributesOfItem(atPath: source.path)
            let handle = try FileHandle(forWritingTo: source)
            try handle.write(contentsOf: Data([0]))
            try handle.close()
            try FileManager.default.setAttributes([.modificationDate: attrs[.modificationDate]!], ofItemAtPath: source.path)
            var moved = false
            #expect(throws: (any Error).self) { try cleanup.perform { moved = true; return $0 } }
            #expect(!moved)
        }
        @Test func cleanupDetectsAReplacementWithIdenticalContents() throws {
            let root = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            let source = root.appendingPathComponent("source.rar")
            let old = root.appendingPathComponent("old")
            try FileManager.default.copyItem(at: Bundle.module.resourceURL!.appendingPathComponent("defaultArchives/defaultArchive.rar"), to: source)
            let cleanup = try ExtractionSourceCleanup(source: source, catalog: ArchiveTypeCatalog())
            try FileManager.default.moveItem(at: source, to: old)
            try FileManager.default.copyItem(at: old, to: source)
            var moved = false
            #expect(throws: (any Error).self) { try cleanup.perform { moved = true; return $0 } }
            #expect(!moved)
        }
        @Test func cleanupRestoresEarlierVolumesOnFailure() throws {
            let root = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            let fixture = Bundle.module.resourceURL!.appendingPathComponent("defaultArchives/defaultArchive.rar")
            for name in ["one.rar", "one.r00"] { try FileManager.default.copyItem(at: fixture, to: root.appendingPathComponent(name)) }
            let cleanup = try ExtractionSourceCleanup(source: root.appendingPathComponent("one.rar"), catalog: ArchiveTypeCatalog())
            var calls = 0
            #expect(throws: (any Error).self) {
                try cleanup.perform { source in
                    calls += 1
                    if calls == 2 { throw CocoaError(.fileWriteNoPermission) }
                    let moved = root.appendingPathComponent("trashed")
                    try FileManager.default.moveItem(at: source, to: moved)
                    return moved
                }
            }
            #expect(cleanup.sources.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        }
        @Test func extractionRejectsExistingSymlinkParents() throws {
            let root = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            let output = root.appendingPathComponent("output")
            let outside = root.appendingPathComponent("outside")
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: output.appendingPathComponent("payload"), withDestinationURL: outside)
            let fixture = Bundle.module.url(forResource: "zip", withExtension: nil)!.appendingPathComponent("appbundle.zip")
            let archive = try SevenZipArchive(url: fixture)
            #expect(throws: (any Error).self) { try archive.extractAll(to: output) }
            #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
        }
        @Test func symlinkTargetsStayWithinExtractionRoot() {
            #expect(!sz_is_safe_symlink_target("pivot", "/outside"))
            #expect(!sz_is_safe_symlink_target("pivot", "../outside"))
            #expect(!sz_is_safe_symlink_target("a/pivot", "../../outside"))
            #expect(sz_is_safe_symlink_target("a/pivot", "../inside"))
            #expect(sz_is_safe_symlink_target("a/pivot", "bin"))
        }
        @Test func tarballChoicesAreAvailableWithoutVolumeParts() {
            let choices = DefaultArchiveAssociations.choices(catalog: ArchiveTypeCatalog())
            let extensions = choices.flatMap(\.extensions)
            for ext in ["tgz", "tbz2", "txz"] { #expect(extensions.contains(ext)) }
            #expect(!extensions.contains("r00"))
            #expect(!extensions.contains("001"))
        }
        @Test func launchFallbackOnlyAppliesBeforeFirstRequest() {
            var session = FinderOperationSession(isTransient: true)
            #expect(session.needsLaunchFallback)
            let request = session.begin()
            #expect(!session.needsLaunchFallback)
            session.finish(request)
            #expect(!session.needsLaunchFallback)
        }
    }
}
