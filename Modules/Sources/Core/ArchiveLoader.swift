//
//  ArchiveLoader.swift
//  Modules
//
//  Created by Stephan Arenswald on 24.12.25.
//

import Foundation
import tb

/// Loader diagnostics are logged independently of the semantic processing
/// activities forwarded to the UI.
private let log = tb.Logger(subsystem: "app.MacPacker", category: "loader")

struct ArchiveLoaderLoadResult: Sendable {
    let type: ArchiveTypeDto
    let compositionType: CompositionTypeDto?
    let root: ArchiveItem
    let entries: [UUID: ArchiveItem]
    let error: String?
    let tempDirectory: URL?
    let uncompressedSize: Int64?
    let hasTree: Bool
    /// True when at least one entry in the archive is encrypted.
    let isEncrypted: Bool
    /// The engine that actually read the archive. Differs from the configured
    /// one when the loader had to fall back; the caller pins it so extraction
    /// uses the same engine.
    let engineType: ArchiveEngineType?
    /// For a split archive, the resolved first volume — so the window shows the
    /// canonical `.z01`/`.zip.001` regardless of which part was opened. nil otherwise.
    let firstVolumeURL: URL?
}

struct ArchiveLoaderBuildTreeResult {
    let error: String?
    /// The entries *after* the tree was built — including the directories
    /// `buildTree` had to synthesize. `ArchiveLoaderLoadResult.entries` is a
    /// snapshot taken before that and does not contain them.
    let entries: [UUID: ArchiveItem]
}

final actor ArchiveLoader {
    private let archiveTypeDetector: ArchiveTypeDetector
    private let archiveEngineSelector: ArchiveEngineSelectorProtocol
    private let passwordResolver: ArchivePasswordResolver
    private let folderAccessResolver: ArchiveFolderAccessResolver

    private var entries: [UUID: ArchiveItem] = [:]
    private var engine: (any ArchiveEngine)?
    
    // status passthrough from the engine to the UI
    private var statusContinuation: AsyncStream<EngineStatus>.Continuation?
    private lazy var status: AsyncStream<EngineStatus> = {
        AsyncStream { continuation in
            self.statusContinuation = continuation
            continuation.yield(.idle)
        }
    }()
    
    public init(
        archiveTypeDetector: ArchiveTypeDetector,
        archiveEngineSelector: ArchiveEngineSelectorProtocol,
        passwordResolver: @escaping ArchivePasswordResolver,
        folderAccessResolver: @escaping ArchiveFolderAccessResolver = { _ in true }
    ) {
        self.archiveTypeDetector = archiveTypeDetector
        self.archiveEngineSelector = archiveEngineSelector
        self.passwordResolver = passwordResolver
        self.folderAccessResolver = folderAccessResolver
    }

    /// Whether the engine currently selected for `type` declares `capability`.
    private func engineDeclares(_ capability: String, for type: ArchiveTypeDto) -> Bool {
        guard let selected = archiveEngineSelector.engineType(for: type.id),
              let engine = type.engines.first(where: { $0.id == selected.configId }) else {
            return false
        }
        return engine.capabilities.contains(capability)
    }

    /// Returns the status stream to the UI
    /// - Returns: status stream from the underlying engine that is doing the actual extraction
    public func statusStream() -> AsyncStream<EngineStatus> {
        return status
    }
    
    /// Forwards the status from the engine to the UI (this is just a bridge)
    /// - Parameter s: the new engine status reported by the engine
    public func yield(_ s: EngineStatus) {
        statusContinuation?.yield(s)
    }
    
    private func forwardStatus(from engine: any ArchiveEngine) -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            for await s in await engine.statusStream() {
                await self.yield(s)
            }
        }
    }
    
    /// Cancels the loading progress
    public func cancel() async {
        guard let engine else { return }
        await engine.cancel()
    }
    
    /// Opens the given URL, assuming this is an archive. `loadEntries(url:)` will figure out the
    /// archive type, select the proper engine and then load all info like type info, entries,  ... . The hiarchy is built in a separate step.
    /// - Parameter url: The url to open
    public func loadEntries(url: URL) async throws -> ArchiveLoaderLoadResult {
        // in case this is a compount `archiveUrl` will hold the extracted url
        var archiveUrl: URL? = url
        // for a split, the resolved first volume (adopted as the window identity)
        var firstVolumeURL: URL? = nil
        var compoundTempUrl: URL? = nil
        
        guard let detectorResult = archiveTypeDetector.detect(for: url, considerComposition: true) else {
            log.notice("No archive type detected", context: [
                "file": url.lastPathComponent,
                "ext": url.pathExtension
            ])
            throw ArchiveError.invalidArchive(
                "\(url.lastPathComponent) is not a recognised archive type.")
        }
        log.info("Archive type detected", context: [
            "file": url.lastPathComponent,
            "type": detectorResult.type.id,
            "composition": detectorResult.composition?.id ?? "none",
            "split": detectorResult.split == nil ? "no" : "yes"
        ])
        
        if let compound = detectorResult.composition {
            // this is a compound, in which case we decompress first,
            // then check the actual archive later
            
            guard let engine = archiveEngineSelector.engine(for: compound.components.last!) else {
                throw ArchiveError.extractionFailed("Could not find engine for detected archive type")
            }
            self.engine = engine
            yield(.processing(
                progress: nil,
                activity: .engineLoaded(name: String(describing: type(of: engine)), typeID: nil)
            ))
            
            // build the status stream to forward the engine status to the UI
            let forwardTaskCompound = forwardStatus(from: engine)
            defer { forwardTaskCompound.cancel() }
            
            let archiveSupportUtilities = ArchiveSupportUtilities()
            guard let temp = archiveSupportUtilities.createTempDirectory() else {
                throw ArchiveError.extractionFailed("Could not create temporary directory")
            }
            compoundTempUrl = temp.url
            yield(.processing(progress: nil, activity: .temporaryDirectoryCreated(temp.url)))
            
            let loaderResult = try await Sandbox.access(url: url) {
                try await engine.loadArchive(
                    url: url,
                    passwordResolver: passwordResolver
                )
            }
            let entries = loaderResult.items
            yield(.processing(progress: nil, activity: .entriesFound(entries.count)))
            
            guard entries.count > 0 else {
                throw ArchiveError.extractionFailed("Extraction of \(url.lastPathComponent) resulted in no files")
            }
            
            let extractedArchiveURL = try await Sandbox.access(url: url) {
                try await engine.extract(
                    item: entries.first!.value,
                    from: url,
                    to: temp.url,
                    passwordResolver: passwordResolver
                )
            }
            archiveUrl = extractedArchiveURL
            yield(.processing(progress: nil, activity: .entryExtracted(extractedArchiveURL)))
        } else if let split = detectorResult.split {
            // A split archive — same shape as the compound step: reduce any volume to
            // the real archive (its first segment). First the selected engine must be
            // able to read split volumes, and we must hold folder access for the
            // siblings — requested through the app via the resolver, exactly like a
            // password. The read itself is wrapped in `Sandbox.access`.
            guard engineDeclares("splitVolumes", for: detectorResult.type) else {
                throw ArchiveError.invalidArchive("The engine selected for \(detectorResult.type.name) can't read split archives. Switch to 7-Zip in Settings.")
            }
            let firstVolume = SplitVolumeResolver.firstVolume(for: url, split: split)
            guard await folderAccessResolver(firstVolume) else {
                throw ArchiveError.invalidArchive("Access to the folder of \(firstVolume.lastPathComponent) was declined; the other volumes can't be read.")
            }
            archiveUrl = firstVolume
            firstVolumeURL = firstVolume
            yield(.processing(progress: nil, activity: .splitFirstVolume(firstVolume.lastPathComponent)))
        }

        guard let archiveUrl else {
            yield(.processing(progress: nil, activity: .archiveURLLost(typeID: detectorResult.type.id)))
            throw ArchiveError.invalidArchive("Somehow we lost the archiveUrl while decompressing")
        }
        
        // This is either the original archive, or the extracted archive from the
        // compound
        yield(.processing(progress: nil, activity: .loadingEngine(typeID: detectorResult.type.id)))
        guard let engine = archiveEngineSelector.engine(for: detectorResult.type.id) else {
            yield(.processing(progress: nil, activity: .invalidArchiveType(typeID: detectorResult.type.id)))
            log.error("No engine for archive type", context: ["type": detectorResult.type.id])
            throw ArchiveError.invalidArchive(
                "No engine is configured for \(detectorResult.type.name).")
        }
        self.engine = engine
        // Which engine actually ran is the single most useful fact when an open
        // fails — the same archive behaves differently on 7-Zip and XAD.
        log.info("Engine selected", context: [
            "file": url.lastPathComponent,
            "type": detectorResult.type.id,
            "engine": archiveEngineSelector.engineType(for: detectorResult.type.id)?.configId ?? "unknown"
        ])
        yield(.processing(
            progress: nil,
            activity: .engineLoaded(name: String(describing: type(of: engine)), typeID: detectorResult.type.id)
        ))
        
        // build the status stream to forward the engine status to the UI
        let forwardTask = forwardStatus(from: engine)
        defer { forwardTask.cancel() }
        
        // set the entries
        let (engineLoadResult, usedEngine) = try await loadArchiveWithFallback(
            url: archiveUrl,
            type: detectorResult.type,
            selected: engine
        )
        self.entries = engineLoadResult.items
        yield(.processing(progress: nil, activity: .entriesFound(self.entries.count)))
        
        // build the hierarchy
        let root = ArchiveItem(name: url.lastPathComponent, type: .root)
        root.set(url: archiveUrl, typeId: detectorResult.type.id)
        
        // Make sure top level entries are linked to the virtual root so they
        // are not orphaned
        if engineLoadResult.hasTree {
            for item in self.entries.values where item.parent == nil {
                item.parent = root.id
                root.addChild(item.id)
            }
        }
        
        // create the loader results
        let result = ArchiveLoaderLoadResult(
            type: detectorResult.type,
            compositionType: detectorResult.composition,
            root: root,
            entries: self.entries,
            error: nil,
            tempDirectory: compoundTempUrl,
            uncompressedSize: engineLoadResult.uncompressedSize,
            hasTree: engineLoadResult.hasTree,
            isEncrypted: engineLoadResult.isEncrypted,
            engineType: usedEngine,
            firstVolumeURL: firstVolumeURL
        )
        return result
    }
    
    /// Reads the archive with the configured engine, falling back to the other
    /// engines the catalog lists for the format if that one simply cannot open
    /// it.
    ///
    /// A format's engines are not interchangeable per archive: XAD is a valid
    /// choice for `rar` and `7zip` but cannot open a header-encrypted archive of
    /// either, so a user with XAD selected got "Unsupported or invalid archive"
    /// for a file 7-Zip reads fine. Telling them to change a setting is a poor
    /// answer when the app can just use the engine that works.
    ///
    /// Only `invalidArchive` triggers a retry — that is the engine saying "I
    /// can't read this". A cancelled password prompt or a genuine extraction
    /// error is final, so the user is never asked for a password twice.
    private func loadArchiveWithFallback(
        url: URL,
        type: ArchiveTypeDto,
        selected: any ArchiveEngine
    ) async throws -> (ArchiveEngineLoadResult, ArchiveEngineType?) {
        let selectedType = archiveEngineSelector.engineType(for: type.id)
        do {
            let result = try await Sandbox.access(url: url) {
                try await selected.loadArchive(url: url, passwordResolver: passwordResolver)
            }
            return (result, selectedType)
        } catch ArchiveError.invalidArchive(let reason) {
            // Manual mode: the user chose this engine, so its limits are the
            // answer, not something to route around.
            guard archiveEngineSelector.allowsEngineFallback else {
                log.notice("Engine cannot read archive, fallback disabled", context: [
                    "file": url.lastPathComponent,
                    "engine": selectedType?.configId ?? "unknown",
                    "reason": reason
                ])
                throw ArchiveError.invalidArchive(reason)
            }

            let alternatives = type.engines
                .compactMap { ArchiveEngineType(configId: $0.id) }
                .filter { $0 != selectedType }

            for candidate in alternatives {
                let engine = archiveEngineSelector.engine(for: candidate)
                do {
                    let result = try await Sandbox.access(url: url) {
                        try await engine.loadArchive(url: url, passwordResolver: passwordResolver)
                    }
                    log.notice("Engine fallback", context: [
                        "file": url.lastPathComponent,
                        "from": selectedType?.configId ?? "unknown",
                        "to": candidate.configId,
                        "reason": reason
                    ])
                    self.engine = engine
                    return (result, candidate)
                } catch ArchiveError.invalidArchive {
                    // This engine can't read it either — try the next one.
                    continue
                }
                // Anything else is a real outcome and belongs to the caller:
                // a dismissed password prompt is the user's answer, cancellation
                // is the user's answer, and a genuine failure is information.
                // Swallowing them here reported the *first* engine's "can't read
                // this" instead, blaming an engine the user never chose.
            }
            throw ArchiveError.invalidArchive(reason)
        }
    }

    /// Builds the hierarchy from the list of entries for the given root. The root can be the entry of the opened
    /// archive, or an item in the archive that is an archive itself
    /// - Parameter root: root to attache the tree to
    /// - Returns: tree of items
    func buildTree(at root: ArchiveItem) -> ArchiveLoaderBuildTreeResult {

        func normalizePath(_ vp: String) -> String {
            var p = vp
            if p.hasSuffix("/") { p = String(p.dropLast()) }
            if p.isEmpty { return "/" }
            if !p.hasPrefix("/") { p = "/" + p }
            return p
        }

        func parentPath(of vp: String) -> String {
            let normalized = normalizePath(vp)
            if let lastSlash = normalized.lastIndex(of: "/"),
               lastSlash != normalized.startIndex {
                return String(normalized[..<lastSlash])
            }
            return "/"
        }

        var dirByPath: [String: ArchiveItem] = ["/": root]

        // ── Pass 1: pre-register every real directory by its path ──
        // This guarantees ensureDirectory never creates a virtual for a real dir.
        for item in entries.values where item.type == .directory {
            guard let vp = item.virtualPath else { continue }
            dirByPath[normalizePath(vp)] = item
        }

        // ── ensureDirectory: find or create the directory at `dirPath` ──
        func ensureDirectory(path dirPath: String) -> ArchiveItem {
            if let existing = dirByPath[dirPath] { return existing }

            var currentPath = "/"
            var parent = root

            for segment in dirPath.dropFirst().split(separator: "/") {
                let name = String(segment)
                let nextPath = currentPath == "/"
                    ? "/\(name)"
                    : "\(currentPath)/\(name)"

                if let cached = dirByPath[nextPath] {
                    // Link to parent if not yet linked
                    if cached.parent == nil && cached !== root {
                        cached.parent = parent.id
                        parent.addChild(cached.id)
                    }
                    parent = cached
                } else {
                    // Create virtual intermediate
                    let n = ArchiveItem(
                        name: name, virtualPath: nil,
                        type: .virtual, parent: parent.id
                    )
                    parent.addChild(n.id)
                    dirByPath[nextPath] = n
                    entries[n.id] = n   // visible to loadChildren
                    parent = n
                }
                currentPath = nextPath
            }
            return parent
        }

        // ── Pass 2: link every entry to its parent ──
        yield(.processing(progress: nil, activity: .buildingTree))

        var i = 0
        let total = entries.count
        for item in entries.values {
            if item === root { continue }
            if item.parent != nil { continue }   // already linked by ensureDirectory

            guard let vp = item.virtualPath else {
                item.parent = root.id
                root.addChild(item.id)
                continue
            }

            let parent = ensureDirectory(path: parentPath(of: vp))
            item.parent = parent.id
            parent.addChild(item.id)

            if i % 1000 == 0 {
                yield(.processing(
                    progress: Double(i) / Double(total) * 100,
                    activity: .buildingTree
                ))
            }
            i += 1
        }

        return ArchiveLoaderBuildTreeResult(error: nil, entries: entries)
    }
}
