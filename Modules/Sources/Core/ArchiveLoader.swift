//
//  ArchiveLoader.swift
//  Modules
//
//  Created by Stephan Arenswald on 24.12.25.
//

import Foundation

struct ArchiveLoaderLoadResult: Sendable {
    let type: ArchiveTypeDto
    let root: ArchiveItem
    let entries: [ArchiveItem]
    let error: String?
}

struct ArchiveLoaderBuildTreeResult {
    let error: String?
}

final actor ArchiveLoader {
    private let archiveTypeDetector: ArchiveTypeDetector
    private let archiveEngineSelector: ArchiveEngineSelectorProtocol
    
    private var entries: [ArchiveItem] = []
    
    public init(
        archiveTypeDetector: ArchiveTypeDetector,
        archiveEngineSelector: ArchiveEngineSelectorProtocol
    ) {
        self.archiveTypeDetector = archiveTypeDetector
        self.archiveEngineSelector = archiveEngineSelector
    }
    
    /// Opens the given URL, assuming this is an archive. `openAsync(url:)` will figure out the
    /// archive type, select the proper engine and then load all info like type info, entries, hierarchy ... .
    /// - Parameter url: The url to open
    public func loadEntries(url: URL) async throws -> ArchiveLoaderLoadResult {
        // in case this is a compount `archiveUrl` will hold the extracted url
        var archiveUrl: URL? = url
        
        guard let detectorResult = archiveTypeDetector.detect(for: url, considerComposition: true) else {
            throw ArchiveError.invalidArchive("Could not detect archive type")
        }
        
        if let compound = detectorResult.composition {
            // this is a compound, in which case we decompress first,
            // then check the actual archive later
            
            guard let engine = archiveEngineSelector.engine(for: compound.components.last!) else {
                throw ArchiveError.extractionFailed("Could not find engine for detected archive type")
            }
            
            let archiveSupportUtilities = ArchiveSupportUtilities()
            guard let temp = archiveSupportUtilities.createTempDirectory() else {
                throw ArchiveError.extractionFailed("Could not create temporary directory")
            }
            
            let entries = try await engine.loadArchive(url: url)
            
            guard entries.count > 0 else {
                throw ArchiveError.extractionFailed("Extraction of \(url.lastPathComponent) resulted in no files")
            }
            
            archiveUrl = try await engine.extract(item: entries[0], from: url, to: temp.url)
        }
        
        // This is either the original archive, or the extracted archive from the
        // compound
        guard let engine = archiveEngineSelector.engine(for: detectorResult.type.id) else {
            throw ArchiveError.invalidArchive("Could not find engine for detected archive type")
        }
        guard let archiveUrl else {
            throw ArchiveError.invalidArchive("Somehow we lost the archiveUrl while decompressing")
        }
        
        // treat the composition here > if this is a tar.bz2 (or any
        // other composition, then decompress first
        
        // set the entries
        print("1: \(Date.now)")
        self.entries = try await engine.loadArchive(url: archiveUrl)
        
        print("2: \(Date.now)")
//        self.entries = Dictionary(uniqueKeysWithValues: enries.map({ ($0.id, $0) }))
        print("3: \(Date.now)")
        
        // build the hierarchy
        let root = ArchiveItem(name: url.lastPathComponent, type: .root)
        root.set(url: archiveUrl, typeId: detectorResult.type.id)
        
        // create the loader results
        let result = ArchiveLoaderLoadResult(
            type: detectorResult.type,
            root: root,
            entries: self.entries,
            error: nil
        )
        return result
    }
    
    func buildTree(at root: ArchiveItem) -> ArchiveLoaderBuildTreeResult {
        print("4a: \(Date.now)")
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
        }
        
        print("4b: \(Date.now)")
        
        let result = ArchiveLoaderBuildTreeResult(
            error: nil
        )
        return result
    }
}
