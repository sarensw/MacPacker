//
//  ArchiveSaver.swift
//  Modules
//
//  Writes an archive to disk — a new one, a Save, a Save As — as ArchiveLoader
//  reads one and ArchiveExtractor extracts from one. The window's ArchiveState
//  keeps what it shows; this is the write itself, with what it may need on the
//  way: access to the files a save adds, access to the folder, and the source
//  archive's password.
//

import Foundation
import Swift7zip
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "archive")

/// Off the main actor, like the loader and the extractor: only the progress it
/// reports goes back there.
final actor ArchiveSaver {
    /// What a save wrote: the file to open again — the first volume, when the
    /// archive was split — and the password that opens it, if it takes one.
    struct Saved: Sendable {
        let url: URL
        let password: String?
    }

    /// The archive on disk the save starts from; `nil` for a new one.
    private let source: URL?
    /// The name the window shows when `source` is a volume of a split archive
    /// — `x.zip` for `x.zip.001` — and `nil` for a single file. Only the name:
    /// nothing is read to know it.
    private let splitArchiveName: String?
    private let target: URL
    private let items: [ArchiveUpdateItem]
    private let options: SevenZipCompressionOptions
    /// A Save As writes every entry again with `options`, onto the source's own
    /// file too. A Save updates the archive in place: what it keeps stays as is.
    private let isSaveAs: Bool
    /// The source's password, when it is known already.
    private let sourcePassword: String?
    private let passwordResolver: ArchivePasswordResolver
    private let folderAccessProvider: ArchiveFolderAccessUserProvider?
    /// Percent written, on the main actor.
    private let onProgress: @MainActor @Sendable (Int) -> Void

    /// How often the source's password is asked for before the save gives up.
    static let passwordPrompts = 5

    init(
        source: URL?,
        splitArchiveName: String?,
        target: URL,
        items: [ArchiveUpdateItem],
        options: SevenZipCompressionOptions,
        isSaveAs: Bool,
        sourcePassword: String?,
        passwordResolver: @escaping ArchivePasswordResolver,
        folderAccessProvider: ArchiveFolderAccessUserProvider?,
        onProgress: @escaping @MainActor @Sendable (Int) -> Void
    ) {
        self.source = source
        self.splitArchiveName = splitArchiveName
        self.target = target
        self.items = items
        self.options = options
        self.isSaveAs = isSaveAs
        self.sourcePassword = sourcePassword
        self.passwordResolver = passwordResolver
        self.folderAccessProvider = folderAccessProvider
        self.onProgress = onProgress
    }

    func save() async throws -> Saved {
        // A set of volumes is not changed in place — 7-Zip does not update one
        // either, and a new file over the first volume would leave the others to
        // be read as part of it. Save As writes the change elsewhere.
        if let splitArchiveName, let source, target.standardizedFileURL == source.standardizedFileURL {
            log.notice("Refusing to save a split archive in place", context: ["file": source.lastPathComponent])
            throw ArchiveError.saveRefused(
                "\(splitArchiveName) is split into volumes, so it can't be changed in place. Use Save As to write it as a new archive.")
        }
        let password = try await write(prompts: 0, sourcePassword: sourcePassword)
        let written = (options.volumeSize ?? 0) > 0
            ? target.deletingLastPathComponent().appendingPathComponent(target.lastPathComponent + ".001")
            : target
        // the password just set for it, or else the source's, which a copy or an
        // update keeps
        return Saved(url: written, password: options.password ?? password)
    }

    /// Writes, and writes again after each answer while the source's password is
    /// missing or wrong — at most `passwordPrompts` answers. Returns the password
    /// that worked.
    private func write(prompts: Int, sourcePassword: String?) async throws -> String? {
        do {
            try await writeWithFolderAccess(sourcePassword: sourcePassword)
            return sourcePassword
        } catch where source != nil && prompts < Self.passwordPrompts && Self.isWrongPassword(error) != nil {
            let attempt = prompts + 1
            let wrong = Self.isWrongPassword(error) == true
            log.notice("Save needs the source archive's password", context: [
                "attempt": "\(attempt)", "wrong": "\(wrong)"
            ])
            // Asked for the way extraction asks. A wrong one counts as a repeat
            // request, which drops it from the cache so it is not tried again.
            let request = ArchivePasswordRequest(url: source!, attempt: wrong ? max(attempt, 2) : attempt)
            guard let answer = await passwordResolver(request) else { throw error }
            return try await write(prompts: attempt, sourcePassword: answer)
        }
    }

    /// The archive may have been opened with a read-only grant (e.g. a path
    /// handed over without a powerbox grant), and the volumes of a split save
    /// sit beside the file the save panel granted. Either write fails with a
    /// no-permission error: ask for folder access exactly like the split-volume
    /// loader does, and retry once.
    private func writeWithFolderAccess(sourcePassword: String?) async throws {
        do {
            try await writeOnce(sourcePassword: sourcePassword)
        } catch where Self.isPermissionError(error) {
            log.notice("Save hit a permission error — asking for folder access", context: ["target": target.lastPathComponent])
            guard let folderAccessProvider, await folderAccessProvider(target) else { throw error }
            try await writeOnce(sourcePassword: sourcePassword)
        }
    }

    /// The write is a long synchronous C call: kept off the cooperative pool,
    /// inside any stored security-scoped grant for the target.
    private func writeOnce(sourcePassword: String?) async throws {
        // Directories as well as files: a folder entry stores no contents, but
        // the writer reads the folder's own extended attributes to store its
        // metadata — a custom folder icon lives there. Without the grant that
        // read is refused under the sandbox and the metadata is dropped silently,
        // which is invisible to the unit tests because they do not run sandboxed.
        var accessedFiles: [URL] = []
        for item in items {
            let diskPath: URL?
            switch item {
            case .addFile(_, let url, _, _): diskPath = url
            case .addDirectory(_, let url, _, _): diskPath = url
            default: diskPath = nil
            }
            if let diskPath, diskPath.startAccessingSecurityScopedResource() {
                accessedFiles.append(diskPath)
            }
        }
        defer { for f in accessedFiles { f.stopAccessingSecurityScopedResource() } }

        let (source, target, items, options, rewrite) = (source, target, items, options, isSaveAs)
        let progress = progressHandler()
        let work: @Sendable () throws -> Void = {
            try SevenZipArchive.writeArchive(
                source: source,
                destination: target,
                items: items,
                options: options,
                sourcePassword: sourcePassword,
                rewrite: rewrite,
                progress: progress
            )
        }
        try await Sandbox.access(url: target) {
            try await runBlocking(work)
        }
    }

    /// 7-Zip's byte progress as a percentage. The callback fires on the writing
    /// (GCD) thread: throttled, then passed to the main actor.
    private func progressHandler() -> @Sendable (UInt64, UInt64) -> Bool {
        let throttle = ProgressThrottle()
        let onProgress = onProgress
        return { completed, total in
            guard total > 0 else { return true }
            let percent = Int((completed * 100) / total)
            if throttle.shouldEmit(at: Date()) {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { onProgress(percent) }
                }
            }
            return true
        }
    }

    private static func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain,
           ns.code == NSFileWriteNoPermissionError || ns.code == NSFileReadNoPermissionError {
            return true
        }
        if case SevenZipError.writeFailed(let message) = error {
            return message.contains("Cannot create output file") || message.contains("Cannot open")
        }
        return false
    }

    /// Whether `error` says the source's password was wrong (`true`) or missing
    /// (`false`); `nil` when it is about something else.
    private static func isWrongPassword(_ error: Error) -> Bool? {
        switch error as? SevenZipError {
        case .passwordWrong?: true
        case .passwordMissing?: false
        default: nil
        }
    }
}

extension Array where Element == ArchiveUpdateItem {
    /// Without the `.DS_Store` files these changes would add. Finder writes one
    /// into every folder it shows, and nobody means to archive it. Only additions
    /// go — entries the archive already holds stay — and only files named exactly
    /// `.DS_Store`: a folder of that name is not Finder's.
    func excludingDSStore() -> [ArchiveUpdateItem] {
        filter { item in
            switch item {
            case .addFile(let path, _, _, _), .addData(let path, _, _, _):
                return (path as NSString).lastPathComponent != ".DS_Store"
            default:
                return true
            }
        }
    }
}
