//
//  ArchiveLoader.swift
//  Modules
//
//  Created by Stephan Arenswald on 24.12.25.
//

import Foundation

struct ArchiveLoaderLoadResult: Sendable {
    let type: ArchiveTypeDto
    let compositionType: CompositionTypeDto?
    let root: ArchiveItem
    let entries: [UUID: ArchiveItem]
    let error: String?
    let tempDirectory: URL?
    let uncompressedSize: Int64?
    let hasTree: Bool
}

struct ArchiveLoaderBuildTreeResult {
    let error: String?
}

final actor ArchiveLoader {
    private let archiveTypeDetector: ArchiveTypeDetector
    private let archiveEngineSelector: ArchiveEngineSelectorProtocol
    private let passwordResolver: ArchivePasswordResolver
    
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
        passwordResolver: @escaping ArchivePasswordResolver
    ) {
        self.archiveTypeDetector = archiveTypeDetector
        self.archiveEngineSelector = archiveEngineSelector
        self.passwordResolver = passwordResolver
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
        var compoundTempUrl: URL? = nil
        
        guard let detectorResult = archiveTypeDetector.detect(for: url, considerComposition: true) else {
            throw ArchiveError.invalidArchive("Could not detect archive type")
        }
        
        if let compound = detectorResult.composition {
            // this is a compound, in which case we decompress first,
            // then check the actual archive later
            
            guard let engine = archiveEngineSelector.engine(for: compound.components.last!) else {
                throw ArchiveError.extractionFailed("Could not find engine for detected archive type")
            }
            self.engine = engine
            yield(.processing(progress: nil, message: "engine loaded: \(String(describing: type(of: engine)))"))
            
            // build the status stream to forward the engine status to the UI
            let forwardTaskCompound = forwardStatus(from: engine)
            defer { forwardTaskCompound.cancel() }
            
            let archiveSupportUtilities = ArchiveSupportUtilities()
            guard let temp = archiveSupportUtilities.createTempDirectory() else {
                throw ArchiveError.extractionFailed("Could not create temporary directory")
            }
            compoundTempUrl = temp.url
            yield(.processing(progress: nil, message: "temp dir created: \(temp.url)"))
            
            let loaderResult = try await engine.loadArchive(
                url: url,
                passwordResolver: passwordResolver
            )
            let entries = loaderResult.items
            yield(.processing(progress: nil, message: "entries found: \(entries.count)"))
            
            guard entries.count > 0 else {
                throw ArchiveError.extractionFailed("Extraction of \(url.lastPathComponent) resulted in no files")
            }
            
            archiveUrl = try await engine.extract(
                item: entries.first!.value,
                from: url,
                to: temp.url,
                passwordResolver: passwordResolver
            )
            yield(.processing(progress: nil, message: "entry extracted: \(String(describing: archiveUrl))"))
        }
        
        guard let archiveUrl else {
            yield(.processing(progress: nil, message: "archiveUrl lost: \(detectorResult.type.id)"))
            throw ArchiveError.invalidArchive("Somehow we lost the archiveUrl while decompressing")
        }
        
        // This is either the original archive, or the extracted archive from the
        // compound
        yield(.processing(progress: nil, message: "loading engine for: \(detectorResult.type.id)"))
        guard let engine = archiveEngineSelector.engine(for: detectorResult.type.id) else {
            yield(.processing(progress: nil, message: "invalid archive type: \(detectorResult.type.id)"))
            throw ArchiveError.invalidArchive("Could not find engine for detected archive type")
        }
        self.engine = engine
        yield(.processing(progress: nil, message: "engine loaded: \(String(describing: type(of: engine))), for: \(detectorResult.type.id)"))
        
        // build the status stream to forward the engine status to the UI
        let forwardTask = forwardStatus(from: engine)
        defer { forwardTask.cancel() }
        
        // set the entries
        let engineLoadResult = try await engine.loadArchive(
            url: archiveUrl,
            passwordResolver: passwordResolver
        )
        self.entries = engineLoadResult.items
        yield(.processing(progress: nil, message: "entries found: \(self.entries.count)"))
        
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
            hasTree: engineLoadResult.hasTree
        )
        return result
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
        yield(.processing(progress: nil, message: "building tree..."))

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
                    message: "building tree..."
                ))
            }
            i += 1
        }

        return ArchiveLoaderBuildTreeResult(error: nil)
    }
}
