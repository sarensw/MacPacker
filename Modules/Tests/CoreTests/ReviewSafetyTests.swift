import Foundation
import Testing
import Swift7zip
import CSevenZip
import FinderMenu
@testable import Core

extension AllCoreTests {
    struct ReviewSafetyTests {
        @Test func sourceCleanupConfirmationDefaultsOnUntilExplicitlyDisabled() {
            let name = "MacPacker-SourceCleanupConfirmation-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            #expect(Keys.confirmsTrashAfterExtraction(in: defaults))
            defaults.set(false, forKey: Keys.confirmTrashAfterExtraction)
            #expect(!Keys.confirmsTrashAfterExtraction(in: defaults))
            defaults.set(true, forKey: Keys.confirmTrashAfterExtraction)
            #expect(Keys.confirmsTrashAfterExtraction(in: defaults))
        }

        @Test func mergeRejectsLinksThroughExistingExternalTargets() throws {
            let root = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            let staged = root.appendingPathComponent("staged")
            let target = root.appendingPathComponent("target")
            let outside = root.appendingPathComponent("outside")
            for folder in [staged, target, outside] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false) }
            try FileManager.default.createSymbolicLink(at: target.appendingPathComponent("external"), withDestinationURL: outside)
            try FileManager.default.createSymbolicLink(atPath: staged.appendingPathComponent("alias").path, withDestinationPath: "external/file")
            #expect(throws: (any Error).self) { try ExtractionDestination.install(staged: staged, target: target, choice: .merge) }
            #expect(try FileManager.default.contentsOfDirectory(atPath: target.path) == ["external"])
        }
        @Test func chainedParentLinksCannotEscapeButSafeChainsWork() throws {
            let root = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            let staged = root.appendingPathComponent("staged")
            let target = root.appendingPathComponent("target")
            try FileManager.default.createDirectory(at: staged.appendingPathComponent("x"), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(atPath: staged.appendingPathComponent("x/l").path, withDestinationPath: "..")
            try FileManager.default.createSymbolicLink(atPath: staged.appendingPathComponent("y").path, withDestinationPath: "x/l/..")
            #expect(!sz_is_safe_resolved_symlink(staged.path, "y"))
            #expect(throws: (any Error).self) { try ExtractionDestination.install(staged: staged, target: target, choice: .merge) }
            #expect(!FileManager.default.fileExists(atPath: target.path))
            try FileManager.default.removeItem(at: staged.appendingPathComponent("y"))
            try FileManager.default.createSymbolicLink(atPath: staged.appendingPathComponent("y").path, withDestinationPath: "x/l/x")
            #expect(sz_is_safe_resolved_symlink(staged.path, "y"))
            _ = try ExtractionDestination.install(staged: staged, target: target, choice: .merge)
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: target.appendingPathComponent("y").path) == "x/l/x")
        }
        @Test func resolvedLinksRejectCyclesAndUseTheReplacementTree() throws {
            let root = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            let staged = root.appendingPathComponent("staged")
            let target = root.appendingPathComponent("target")
            for folder in [staged, target] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false) }
            try FileManager.default.createSymbolicLink(atPath: staged.appendingPathComponent("a").path, withDestinationPath: "b")
            try FileManager.default.createSymbolicLink(atPath: staged.appendingPathComponent("b").path, withDestinationPath: "a")
            #expect(!sz_is_safe_resolved_symlink(staged.path, "a"))
            #expect(throws: (any Error).self) { try ExtractionDestination.install(staged: staged, target: target, choice: .replaceAll) }
            try FileManager.default.removeItem(at: staged.appendingPathComponent("b"))
            try Data("inside".utf8).write(to: staged.appendingPathComponent("b"))
            try FileManager.default.createSymbolicLink(atPath: target.appendingPathComponent("b").path, withDestinationPath: "/outside")
            _ = try ExtractionDestination.install(staged: staged, target: target, choice: .replaceAll, trash: { try FileManager.default.removeItem(at: $0) })
            #expect(try String(contentsOf: target.appendingPathComponent("a"), encoding: .utf8) == "inside")
        }
        @Test func mergedLinkChecksHonorReplacedAndSkippedEntries() throws {
            let root = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            let staged = root.appendingPathComponent("staged")
            let target = root.appendingPathComponent("target")
            for folder in [staged, target] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false) }
            try Data("kept".utf8).write(to: target.appendingPathComponent("alias"))
            try FileManager.default.createSymbolicLink(atPath: staged.appendingPathComponent("alias").path, withDestinationPath: "../outside")
            let merged = try ExtractionDestination.install(staged: staged, target: target, choice: .merge)
            #expect(merged.skippedExisting)
            #expect(try String(contentsOf: target.appendingPathComponent("alias"), encoding: .utf8) == "kept")
        }
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
