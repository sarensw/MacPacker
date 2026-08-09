//
//  CompoundArchiveStreamingTests.swift
//  Modules
//

import Foundation
import Testing
@testable import Core
@testable import ArchivePreviewUI
@testable import Swift7zip

private final class StagedCompoundCancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var _started = false
    private var _usedProgress = false
    private var _observedCancellation = false

    var started: Bool { withLock { _started } }
    var usedProgress: Bool { withLock { _usedProgress } }
    var observedCancellation: Bool { withLock { _observedCancellation } }

    func markStarted(usingProgress: Bool) {
        withLock {
            _started = true
            _usedProgress = usingProgress
        }
    }

    func markCancellationObserved() {
        withLock { _observedCancellation = true }
    }

    @discardableResult
    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private actor StagedCompoundCancellationEngine: ArchiveEngine {
    private let probe: StagedCompoundCancellationProbe

    init(probe: StagedCompoundCancellationProbe) {
        self.probe = probe
    }

    func statusStream() -> AsyncStream<EngineStatus> {
        AsyncStream { $0.yield(.idle) }
    }

    func cancel() async {}

    func loadArchive(
        url: URL,
        passwordResolver: @escaping ArchivePasswordResolver
    ) async throws -> ArchiveEngineLoadResult {
        let item = ArchiveItem(
            index: 0,
            name: "inner.tar",
            virtualPath: "inner.tar",
            type: .file,
            uncompressedSize: 1024)
        return ArchiveEngineLoadResult(
            items: [item.id: item],
            hasTree: false,
            uncompressedSize: 1024)
    }

    func extract(
        items: [ArchiveItem],
        from url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver
    ) async throws -> ArchiveExtractionResult {
        probe.markStarted(usingProgress: false)
        try await Task.sleep(for: .milliseconds(300))
        throw ArchiveError.extractionFailed("staged extraction did not receive a cancellation callback")
    }

    func extract(
        items: [ArchiveItem],
        from url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver,
        onProgress: ArchiveExtractionProgress?
    ) async throws -> ArchiveExtractionResult {
        probe.markStarted(usingProgress: true)
        while onProgress?(0, 1024) != false {
            try await Task.sleep(for: .milliseconds(10))
        }
        probe.markCancellationObserved()
        throw CancellationError()
    }

    func extract(
        _ url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver
    ) async throws {
        throw ArchiveError.extractionFailed("not used by this test")
    }
}

private struct StagedCompoundCancellationSelector: ArchiveEngineSelectorProtocol {
    let engineInstance: StagedCompoundCancellationEngine

    func engine(for id: String) -> (any ArchiveEngine)? { engineInstance }
    func engine(for type: ArchiveEngineType) -> any ArchiveEngine { engineInstance }
    func engineType(for id: String) -> ArchiveEngineType? { .xad }
}

private func matchesDefaultArchivePayload(_ extracted: URL, path: String) -> Bool {
    let source = Bundle.module
        .url(forResource: "defaultArchiveContent", withExtension: nil)!
        .appendingPathComponent(path)
    guard let extractedData = try? Data(contentsOf: extracted),
          let sourceData = try? Data(contentsOf: source)
    else { return false }
    return extractedData == sourceData
}

extension AllCoreTests {

    @MainActor struct CompoundArchiveStreamingTests {

        @Test func sevenZipStreamedCompoundLoadDoesNotCreateAStagingDirectory() async throws {
            let catalog = ArchiveTypeCatalog()
            let loader = ArchiveLoader(
                archiveTypeDetector: ArchiveTypeDetector(catalog: catalog),
                archiveEngineSelector: ArchiveEngineSelector7zip(),
                passwordResolver: { _ in nil },
                compoundLoadingStrategy: .streamed,
                tempDirectoryProvider: {
                    Issue.record("streamed compound loading must not stage the inner tar")
                    return nil
                }
            )
            let fixtures = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let archive = fixtures.appendingPathComponent("defaultArchive.tar.xz")

            let result = try await loader.loadEntries(url: archive)
            let names = Set(result.entries.values.map(\.name))

            #expect(result.compositionType?.id == "tar.xz")
            #expect(result.tempDirectory == nil)
            #expect(names == ["folder", "README.md", "NestedArchive.zip", "hello world.txt"])
        }

        @Test func sevenZipRejectsDamagedBoundedXzStream() throws {
            let fixtures = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let source = fixtures.appendingPathComponent("defaultArchive.tar.xz")
            let damaged = FileManager.default.temporaryDirectory
                .appendingPathComponent("damaged-\(UUID().uuidString).tar.xz")
            defer { try? FileManager.default.removeItem(at: damaged) }

            // Keep the real archive's XZ header, index, and footer intact so
            // 7-Zip selects the bounded compound path, but damage compressed
            // bytes that the inner tar scan must decode.
            var bytes = try Data(contentsOf: source)
            let damagedIndex = bytes.index(bytes.startIndex, offsetBy: bytes.count / 2)
            bytes[damagedIndex] ^= 0xFF
            try bytes.write(to: damaged)

            #expect(throws: SevenZipError.self) {
                _ = try SevenZipArchive(
                    url: damaged,
                    drillSingleStream: true
                )
            }
        }

        @Test func cancellingAStagedCompoundStopsExtractionAndRemovesItsTemporaryDirectory() async throws {
            let probe = StagedCompoundCancellationProbe()
            let engine = StagedCompoundCancellationEngine(probe: probe)
            let stagingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(
                at: stagingDirectory,
                withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: stagingDirectory) }

            let catalog = ArchiveTypeCatalog()
            let loader = ArchiveLoader(
                archiveTypeDetector: ArchiveTypeDetector(catalog: catalog),
                archiveEngineSelector: StagedCompoundCancellationSelector(engineInstance: engine),
                passwordResolver: { _ in nil },
                tempDirectoryProvider: { stagingDirectory })
            let fixtures = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let archive = fixtures.appendingPathComponent("defaultArchive.tar.gz")

            let loadTask = Task {
                try await loader.loadEntries(url: archive)
            }
            for _ in 0..<100 where !probe.started {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(probe.started)

            await loader.cancel()

            do {
                _ = try await loadTask.value
                Issue.record("staged compound loading ignored cancellation")
            } catch is CancellationError {
                // Expected.
            } catch {
                Issue.record("expected cancellation, got \(error)")
            }

            #expect(probe.usedProgress)
            #expect(probe.observedCancellation)
            #expect(!FileManager.default.fileExists(atPath: stagingDirectory.path))
        }

        @Test(arguments: [
            "defaultArchive.tar.gz",
            "defaultArchive.tar.bz2",
            "defaultArchive.tar.Z"
        ])
        func xadOuterCompressionHonorsTheStagedCancellationCallback(name: String) async throws {
            let fixtures = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let archive = fixtures.appendingPathComponent(name)
            let engine = ArchiveXadEngine()
            let loaded = try await engine.loadArchive(
                url: archive,
                passwordResolver: { _ in nil })
            let entry = try #require(loaded.items.values.first)
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(
                at: destination,
                withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: destination) }

            do {
                _ = try await engine.extract(
                    items: [entry],
                    from: archive,
                    to: destination,
                    passwordResolver: { _ in nil },
                    onProgress: { _, _ in false })
                Issue.record("XAD ignored the staged cancellation callback for \(name)")
            } catch is CancellationError {
                // Expected.
            }
        }

        @Test func xadListingHonorsTaskCancellation() async throws {
            let fixtures = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let archive = fixtures.appendingPathComponent("defaultArchive.tar")

            let loadTask = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await ArchiveXadEngine().loadArchive(
                    url: archive,
                    passwordResolver: { _ in nil })
            }

            do {
                _ = try await loadTask.value
                Issue.record("XAD listing ignored task cancellation")
            } catch is CancellationError {
                // Expected.
            }
        }

        @Test func previewUsesCancellable7ZipStreamingForTarXz() async throws {
            let fixtures = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let archive = fixtures.appendingPathComponent("defaultArchive.tar.xz")
            let state = ArchivePreviewLoader.makeState()

            state.open(url: archive)
            try await state.openTask?.value

            #expect(state.activeEngine == .`7zip`)
            #expect(state.compositionType?.id == "tar.xz")
            #expect(state.itemCount == 4)
        }

        @Test func streamedTarXzEntriesCanStillBeExtracted() async throws {
            let fixtures = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let archive = fixtures.appendingPathComponent("defaultArchive.tar.xz")
            let engine = Archive7ZipEngine()
            let loaded = try await engine.loadCompoundArchive(
                url: archive,
                passwordResolver: { _ in nil })
            let readme = try #require(loaded.items.values.first { $0.name == "README.md" })
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(
                at: destination, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: destination) }

            let result = try await engine.extract(
                items: [readme],
                from: archive,
                to: destination,
                passwordResolver: { _ in nil })

            let extracted = try #require(result[readme])
            #expect(FileManager.default.fileExists(atPath: extracted.path))
            #expect(matchesDefaultArchivePayload(
                extracted,
                path: "folder/README.md"))
        }

        @Test func streamedTarXzCanStillBeExtractedInFull() async throws {
            let fixtures = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let archive = fixtures.appendingPathComponent("defaultArchive.tar.xz")
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(
                at: destination, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: destination) }

            try await Archive7ZipEngine().extractCompoundArchive(
                archive,
                to: destination,
                passwordResolver: { _ in nil },
                onProgress: nil)

            let extracted = destination.appendingPathComponent("folder/README.md")
            #expect(FileManager.default.fileExists(atPath: extracted.path))
            #expect(matchesDefaultArchivePayload(
                extracted,
                path: "folder/README.md"))
        }
    }
}
