//
//  Archive7ZipEngineNew.swift
//  Modules
//
//  Created by Stephan Arenswald on 27.03.26.
//

import Foundation
import Swift7zip

final actor Archive7ZipEngine: ArchiveEngine {
    private var statusContinuation: AsyncStream<EngineStatus>.Continuation?
    
    func statusStream() -> AsyncStream<EngineStatus> {
        AsyncStream { continuation in
            self.statusContinuation = continuation
            continuation.yield(.idle)
        }
    }
    
    private func emit(_ s: EngineStatus) {
        statusContinuation?.yield(s)
    }
    
    func cancel() async {
    }

    func loadArchive(
        url: URL,
        passwordResolver: @escaping ArchivePasswordResolver
    ) async throws -> ArchiveEngineLoadResult {
        // Split/multi-volume archives are read in place. The caller resolves the
        // canonical entry (`.zip` for spanned, `.001` for numeric) and holds a
        // security-scoped grant on the containing folder, so the C bridge's
        // volume callback opens sibling volumes directly — no staging needed.
        let szip = try await Self.open(
            url: url, attempts: ArchivePasswordAttempts(url: url, resolver: passwordResolver))

        var items: [UUID: ArchiveItem] = [:]
        var uncompressedSizeOverall: Int64 = 0
        var idToUUIDMap: [UInt32: UUID] = [:]
        var isEncrypted = false

        try szip.entries.forEach { entry in
            if entry.isEncrypted { isEncrypted = true }

            var name = entry.path
            let parts = entry.path.split(separator: "/")
            if let last = parts.last {
                name = String(last)
            }
            
            let item: ArchiveItem = .init(
                index: entry.index,
                name: name,
                virtualPath: entry.path,
                type: entry.isDirectory ? .directory : .file,
                parent: nil,
                compressedSize: Int(entry.packedSize),
                uncompressedSize: Int(entry.size),
                modificationDate: entry.modificationDate,
                posixPermissions: entry.posixPermissions.map { Int($0) })
            items[item.id] = item
            idToUUIDMap[entry.index] = item.id
            
            uncompressedSizeOverall += Int64(entry.size)
        }
        
        if szip.isTree {
            // The file type (usually disk images) already provide the hierarchy.
            // So there is no need to recalculate this later. Just one pass here.
            try szip.entries.forEach { entry in
                let index = entry.index
                if
                    // the item itself
                    let uuid = idToUUIDMap[index],
                    let item = items[uuid],
                    // the parent item to make sure the parent knows its children
                    let parentIndex = entry.parentIndex,
                    let parentUUID = idToUUIDMap[parentIndex],
                    let parentItem = items[parentUUID]
                {
                    item.parent = idToUUIDMap[parentIndex]
                    parentItem.addChild(uuid)
                }
            }
        }
        
        return ArchiveEngineLoadResult(
            items: items,
            hasTree: szip.isTree,
            uncompressedSize: uncompressedSizeOverall,
            // A header-encrypted archive needed the password just to list, so
            // it counts as encrypted even if no entry flags itself.
            isEncrypted: isEncrypted || szip.hasPassword
        )
    }
    
    func extract(
        items: [ArchiveItem],
        from url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver
    ) async throws -> ArchiveExtractionResult {
        try await extract(items: items, from: url, to: destination, passwordResolver: passwordResolver, onProgress: nil)
    }

    func extract(
        items: [ArchiveItem],
        from url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver,
        onProgress: ArchiveExtractionProgress?
    ) async throws -> ArchiveExtractionResult {
        guard items.isEmpty == false else {
            throw ArchiveError.extractionFailed("No items to extract")
        }
        
        // get the list of indices first
        var indices: [UInt32: UUID] = [:]
        for item in items {
            if let index = item.index {
                indices[index] = item.id
            }
        }
        let sorted = indices.keys.sorted { $0 < $1 }
        
        let attempts = ArchivePasswordAttempts(url: url, resolver: passwordResolver)
        let szip = try await Self.open(url: url, attempts: attempts)

        // The password is settled by the open above, but a wrong one only shows
        // up here: nothing in a 7z or a zip lets it be checked before an entry is
        // decrypted. Loops until the archive extracts, the user cancels the
        // prompt, or the attempt budget runs out.
        while true {
            do {
                // blocking C call — keep it off the cooperative pool
                let extractedEntries: [UInt32: URL] = try await runBlocking {
                    try szip.extract(indices: sorted, to: destination, progress: Self.bridgeProgress(onProgress))
                }

                let urlsByItemID: [UUID: URL] = Dictionary(
                    uniqueKeysWithValues: extractedEntries.compactMap { (index, url) in
                        guard let uuid = indices[index] else { return nil }
                        return (uuid, url)
                    }
                )

                let result = ArchiveExtractionResult(urlsByItemID: urlsByItemID)

                return result

            } catch SevenZipError.passwordMissing, SevenZipError.passwordWrong {
                szip.setPassword(try await attempts.next())
                continue
            } catch SevenZipError.cancelled {
                throw CancellationError()
            }
        }
    }
    
    func extract(
        _ url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver
    ) async throws {
        try await extract(url, to: destination, passwordResolver: passwordResolver, onProgress: nil)
    }

    func extract(
        _ url: URL,
        to destination: URL,
        passwordResolver: @escaping ArchivePasswordResolver,
        onProgress: ArchiveExtractionProgress?
    ) async throws {
        let attempts = ArchivePasswordAttempts(url: url, resolver: passwordResolver)
        let szip = try await Self.open(url: url, attempts: attempts)

        // Same retry shape as extract(items:): loop until the archive
        // extracts or the user cancels the password prompt.
        while true {
            do {
                // blocking C call — keep it off the cooperative pool
                try await runBlocking {
                    try szip.extractAll(to: destination, progress: Self.bridgeProgress(onProgress))
                }
                return
            } catch SevenZipError.passwordMissing, SevenZipError.passwordWrong {
                szip.setPassword(try await attempts.next())
                continue
            } catch SevenZipError.cancelled {
                throw CancellationError()
            }
        }
    }

    /// Opens the archive with the password it needs, asked for here rather than
    /// when something later fails.
    ///
    /// Two kinds of archive want one. A header-encrypted archive (7z `-mhe=on`,
    /// RAR `-hp`) cannot be listed at all without it, so opening fails until one
    /// is given. An archive with encrypted entries lists fine, and used to be let
    /// through to be asked about at extraction time — but the prompt belongs to
    /// opening the archive for every engine alike, because the XAD engine has to
    /// have it by then: it restores a file's Finder tags while parsing, and a
    /// password handed over afterwards is too late (#246).
    ///
    /// Nobody to ask is not a failure here. An archive whose names read without a
    /// password still lists them, which is what a Quick Look preview and Finder's
    /// "Extract Here" — neither of which carries a prompt — go on showing.
    private static func open(
        url: URL,
        attempts: ArchivePasswordAttempts
    ) async throws -> SevenZipArchive {
        var password: String?
        let archive: SevenZipArchive = try await {
            while true {
                do {
                    return try SevenZipArchive(url: url, password: password)
                } catch SevenZipError.passwordMissing, SevenZipError.passwordWrong {
                    password = try await attempts.next()
                }
            }
        }()

        if !archive.hasPassword, try archive.entries.contains(where: \.isEncrypted),
           let password = try await attempts.nextIfOffered() {
            archive.setPassword(password)
        }
        return archive
    }

    /// Adapts the engine-level progress closure to the bridge's handler.
    private static func bridgeProgress(_ onProgress: ArchiveExtractionProgress?) -> SevenZipArchive.ProgressHandler? {
        guard let onProgress else { return nil }
        return { completed, total in
            onProgress(Int64(clamping: completed), Int64(clamping: total))
        }
    }
}
