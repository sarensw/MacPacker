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
        let szip = try await Self.open(url: url, passwordResolver: passwordResolver)

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
        
        let szip = try await Self.open(url: url, passwordResolver: passwordResolver)

        var attempt = 0
        // Loops until the archive extracts, the user cancels the prompt, or the
        // attempt budget runs out.
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
                attempt += 1
                let password = try await Self.nextPassword(
                    for: url,
                    attempt: attempt,
                    resolver: passwordResolver
                )
                szip.setPassword(password)
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
        let szip = try await Self.open(url: url, passwordResolver: passwordResolver)

        var attempt = 0
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
                attempt += 1
                let password = try await Self.nextPassword(
                    for: url,
                    attempt: attempt,
                    resolver: passwordResolver
                )
                szip.setPassword(password)
                continue
            } catch SevenZipError.cancelled {
                throw CancellationError()
            }
        }
    }

    /// Opens the archive, prompting for a password when the format encrypts its
    /// header (7z `-mhe=on`, RAR `-hp`) — those cannot even be listed without
    /// one. Shared by listing and both extraction paths so the prompt behaves
    /// the same wherever the archive is opened.
    private static func open(
        url: URL,
        passwordResolver: ArchivePasswordResolver
    ) async throws -> SevenZipArchive {
        var password: String?
        var attempt = 0
        while true {
            do {
                return try SevenZipArchive(url: url, password: password)
            } catch SevenZipError.passwordMissing, SevenZipError.passwordWrong {
                attempt += 1
                password = try await nextPassword(
                    for: url,
                    attempt: attempt,
                    resolver: passwordResolver
                )
            }
        }
    }

    /// How many passwords a single operation will ask for before giving up.
    /// A resolver that keeps answering with the same wrong password (a stale
    /// cache, a scripted caller) would otherwise spin forever.
    private static let maxPasswordAttempts = 20

    /// Asks the resolver for the next password to try.
    /// - Throws: ``ArchiveError/passwordCancelled`` when the user dismisses the
    ///   prompt, or ``ArchiveError/extractionFailed(_:)`` once the attempt
    ///   budget is exhausted.
    private static func nextPassword(
        for url: URL,
        attempt: Int,
        resolver: ArchivePasswordResolver
    ) async throws -> String {
        // 7z AES stores no password verifier, so a failed decrypt and a damaged
        // encrypted entry are genuinely indistinguishable — say both rather than
        // insist on the password when we cannot know.
        guard attempt <= maxPasswordAttempts else {
            throw ArchiveError.extractionFailed(
                "Could not decrypt \(url.lastPathComponent) after \(maxPasswordAttempts) attempts. The password may be wrong, or the archive may be damaged.")
        }
        guard let password = await resolver(
            ArchivePasswordRequest(url: url, attempt: attempt)
        ) else {
            throw ArchiveError.passwordCancelled
        }
        return password
    }

    /// Adapts the engine-level progress closure to the bridge's handler.
    private static func bridgeProgress(_ onProgress: ArchiveExtractionProgress?) -> SevenZipArchive.ProgressHandler? {
        guard let onProgress else { return nil }
        return { completed, total in
            onProgress(Int64(clamping: completed), Int64(clamping: total))
        }
    }
}
