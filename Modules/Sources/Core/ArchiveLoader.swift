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
    let entries: [ArchiveItem]
    let error: String?
    let tempDirectory: URL?
    let uncompressedSize: Int64?
}

struct ArchiveLoaderBuildTreeResult {
    let error: String?
}

final actor ArchiveLoader {
    private let archiveTypeDetector: ArchiveTypeDetector
    private let archiveEngineSelector: ArchiveEngineSelectorProtocol
    
    private var entries: [ArchiveItem] = []
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
        archiveEngineSelector: ArchiveEngineSelectorProtocol
    ) {
        self.archiveTypeDetector = archiveTypeDetector
        self.archiveEngineSelector = archiveEngineSelector
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
            
            let loaderResult = try await engine.loadArchive(url: url)
            let entries = loaderResult.items
            yield(.processing(progress: nil, message: "entries found: \(entries.count)"))
            
            guard entries.count > 0 else {
                throw ArchiveError.extractionFailed("Extraction of \(url.lastPathComponent) resulted in no files")
            }
            
            archiveUrl = try await engine.extract(item: entries[0], from: url, to: temp.url)
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
        let engineLoadResult = try await engine.loadArchive(url: archiveUrl)
        self.entries = engineLoadResult.items
        yield(.processing(progress: nil, message: "entries found: \(self.entries.count)"))
        
        // build the hierarchy
        let root = ArchiveItem(name: url.lastPathComponent, type: .root)
        root.set(url: archiveUrl, typeId: detectorResult.type.id)
        
        // create the loader results
        let result = ArchiveLoaderLoadResult(
            type: detectorResult.type,
            compositionType: detectorResult.composition,
            root: root,
            entries: self.entries,
            error: nil,
            tempDirectory: compoundTempUrl,
            uncompressedSize: engineLoadResult.uncompressedSize
        )
        return result
    }
    
    /// Builds the hierarchy from the list of entries for the given root. The root can be the entry of the opened
    /// archive, or an item in the archive that is an archive itself
    /// - Parameter root: root to attache the tree to
    /// - Returns: tree of items
    func buildTree(at root: ArchiveItem) -> ArchiveLoaderBuildTreeResult {
        // #1: per-parent child lookup (already added)
        var childByParent: [ObjectIdentifier: [String: ArchiveItem]] = [:]

        @inline(__always)
        func getChild(_ name: String, of parent: ArchiveItem) -> ArchiveItem? {
            childByParent[ObjectIdentifier(parent)]?[name]
        }

        @inline(__always)
        func setChild(_ child: ArchiveItem, of parent: ArchiveItem) {
            let key = ObjectIdentifier(parent)
            var dict = childByParent[key] ?? [:]
            dict[child.name] = child
            childByParent[key] = dict
        }

        // #2: directory path -> node cache
        var dirByPath: [String: ArchiveItem] = ["/": root]
        dirByPath.reserveCapacity(4096) // rough; grows as needed

        @inline(__always)
        func normalizeDirPath(_ path: Substring) -> String {
            // path is like "/a/b" or "a/b" depending on your input.
            // We’ll normalize to leading "/" and no trailing "/".
            if path.isEmpty { return "/" }
            if path.first == "/" { return String(path) }
            return "/" + path
        }

        @inline(__always)
        func ensureDirectory(path dirPath: String) -> ArchiveItem {
            if let existing = dirByPath[dirPath] { return existing }

            // Create missing directories along the path.
            // We walk from root and create only the missing segments.
            var currentPath = "/"
            var parent = root

            // Strip leading "/"
            let startIdx = dirPath.index(after: dirPath.startIndex)
            let remainder = dirPath[startIdx...]

            var segmentStart = remainder.startIndex
            var i = remainder.startIndex

            while i <= remainder.endIndex {
                let isEnd = (i == remainder.endIndex)
                if isEnd || remainder[i] == "/" {
                    let segment = remainder[segmentStart..<i]
                    if !segment.isEmpty {
                        let name = String(segment)
                        let nextPath = (currentPath == "/") ? "/\(name)" : "\(currentPath)/\(name)"

                        if let cached = dirByPath[nextPath] {
                            parent = cached
                        } else if let existingChild = getChild(name, of: parent) {
                            // Directory already exists as a child (e.g. created earlier)
                            dirByPath[nextPath] = existingChild
                            parent = existingChild
                        } else {
                            let n = ArchiveItem(name: name, virtualPath: nil, type: .directory, parent: parent)
                            parent.addChild(n)
                            setChild(n, of: parent)
                            dirByPath[nextPath] = n
                            parent = n
                        }

                        currentPath = nextPath
                    }
                    if isEnd {
                        break
                    } else {
                        segmentStart = remainder.index(after: i)
                    }

                }
                if isEnd { break }
                i = remainder.index(after: i)
            }

            dirByPath[dirPath] = parent
            return parent
        }
        
        yield(.processing(progress: nil, message: "building tree..."))

        var i = 0
        for entry in entries {
            let vp = entry.virtualPath ?? "/"

            // parentDir = everything before last "/" ("/a/b/c.txt" -> "/a/b")
            if let lastSlash = vp.lastIndex(of: "/") {
                let parentSub = vp[..<lastSlash]
                let parentDir = normalizeDirPath(parentSub)
                let parent = ensureDirectory(path: parentDir)

                // avoid duplicates (folder already created due to deeper files)
                if getChild(entry.name, of: parent) != nil { continue }

                entry.parent = parent
                parent.addChild(entry)
                setChild(entry, of: parent)
            } else {
                // no slash -> treat as direct child of root
                if getChild(entry.name, of: root) != nil { continue }
                entry.parent = root
                root.addChild(entry)
                setChild(entry, of: root)
            }
            
            if i % 1000 == 0 {
                yield(.processing(progress: Double(i) / Double(entries.count) * 100, message: "building tree..."))
            }
            i += 1
        }
        
        let result = ArchiveLoaderBuildTreeResult(
            error: nil
        )
        return result
    }
}
