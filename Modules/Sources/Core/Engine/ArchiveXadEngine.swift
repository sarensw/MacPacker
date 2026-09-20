//
//  ArchiveXadEngine.swift
//  Modules
//
//  Created by Stephan Arenswald on 25.11.25.
//

import Foundation
import XADMaster

/// The one delegate XADArchive allows, doing both jobs that are needed of it.
///
/// The password half is why it has to be installed before the archive is opened
/// rather than after. XADMaster folds a file's AppleDouble sidecar — the Finder
/// tags, the resource fork — back onto the file while it parses the archive,
/// which is inside the open call, and for an encrypted archive that means
/// decrypting the sidecar right there. A sidecar it cannot read is given up on
/// for good, so a password set afterwards restores nothing (#246). `XADArchive`
/// takes a delegate at init and asks it, once, the moment the parse needs a
/// password.
///
/// The progress half relays byte counts to the engine consumer and answers the
/// should-stop poll, so the cancel button aborts a XAD extraction mid-flight.
/// Only our delegate object — vendored XADMaster stays untouched.
private final class XADArchiveDelegate: NSObject, @unchecked Sendable {
    private let lock = NSLock()
    private var password: String?

    private let onProgress: ArchiveExtractionProgress?
    /// Total for per-entry mode, from the items' listing sizes.
    private let totalBytes: Int64
    /// True when the whole-archive extraction runs — XAD then reports
    /// global counters itself and the per-entry callback is ignored.
    private let usesGlobalCounters: Bool
    private var baseBytes: Int64 = 0
    private var stopped = false

    init(
        onProgress: ArchiveExtractionProgress? = nil,
        totalBytes: Int64 = 0,
        usesGlobalCounters: Bool = false
    ) {
        self.onProgress = onProgress
        self.totalBytes = totalBytes
        self.usesGlobalCounters = usesGlobalCounters
    }

    var currentPassword: String? {
        lock.lock()
        defer { lock.unlock() }
        return password
    }

    func setPassword(_ newPassword: String) {
        lock.lock()
        password = newPassword
        lock.unlock()
    }

    @objc(archiveNeedsPassword:)
    override func archiveNeedsPassword(_ archive: XADArchive!) {
        guard let password = currentPassword else { return }
        archive.setPassword(password)
    }

    var wasStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    /// Called by the engine after an entry finished, so the next entry's
    /// per-entry byte counts continue from the right offset.
    func advanceBase(by bytes: Int64) {
        lock.lock()
        defer { lock.unlock() }
        baseBytes += Swift.max(0, bytes)
    }

    private func relay(_ completed: Int64, _ total: Int64) {
        guard let onProgress else { return }
        if !onProgress(completed, total) {
            lock.lock()
            stopped = true
            lock.unlock()
        }
    }

    @objc(archiveExtractionShouldStop:)
    override func archiveExtractionShouldStop(_ archive: XADArchive!) -> Bool {
        wasStopped
    }

    @objc(archive:extractionProgressForEntry:bytes:of:)
    override func archive(_ archive: XADArchive!, extractionProgressForEntry n: Int32, bytes: off_t, of total: off_t) {
        guard !usesGlobalCounters else { return }
        lock.lock()
        let base = baseBytes
        lock.unlock()
        relay(base + Int64(bytes), totalBytes)
    }

    @objc(archive:extractionProgressBytes:of:)
    override func archive(_ archive: XADArchive!, extractionProgressBytes bytes: off_t, of total: off_t) {
        guard usesGlobalCounters else { return }
        relay(Int64(bytes), Int64(total))
    }
}

/// An open XADArchive and the password it was opened with.
///
/// `@unchecked Sendable` for the same reason `runBlocking`'s transfer box is:
/// the engine actor is the only thing that ever holds one, so only one thread
/// touches it at a time. It has to cross an isolation boundary at all because
/// opening now awaits — the password is resolved as part of it.
private final class XADArchiveWithPasswordSupport: @unchecked Sendable {
    private let url: URL
    private let attempts: ArchivePasswordAttempts
    private let delegate: XADArchiveDelegate
    /// Replaced whenever the archive has to be opened again under a new
    /// password, which is also what rebuilds `indicesByPath`.
    private var archive: XADArchive
    private init(
        url: URL,
        attempts: ArchivePasswordAttempts,
        delegate: XADArchiveDelegate,
        archive: XADArchive
    ) {
        self.url = url
        self.attempts = attempts
        self.delegate = delegate
        self.archive = archive
    }

    /// Whether the archive was opened with a password. A header-encrypted
    /// archive needed one just to list, so it counts as encrypted even when no
    /// entry flags itself.
    var wasOpenedWithAPassword: Bool { delegate.currentPassword != nil }

    /// Opens `url`, with a password when the archive turns out to want one.
    ///
    /// The password is settled here rather than when something later fails,
    /// because this call is the one that needs it: it parses the archive, and
    /// everything XADMaster does with a file's Mac metadata happens during that
    /// parse. A header-encrypted archive does not even list without one.
    static func open(
        url: URL,
        attempts: ArchivePasswordAttempts,
        delegate: XADArchiveDelegate
    ) async throws -> XADArchiveWithPasswordSupport {
        while true {
            let (opened, openError) = try await openArchive(at: url, delegate: delegate)

            guard let opened else {
                let looksLikeAPassword = openError == XADPasswordError
                    || passwordSuspectErrors.contains(openError)

                // A header-encrypted archive (7z -mhe=on, RAR -hp) has to be
                // decrypted to be listed at all, and XAD reports failing at that
                // as a plain decrunch error — the same code a genuinely damaged
                // archive gets. So a password is worth one try, but only one: a
                // format XADMaster cannot read fails exactly the same way, and
                // asking the user twenty times for a password that was never the
                // problem is worse than saying so.
                if looksLikeAPassword, delegate.currentPassword == nil,
                   let password = try await attempts.nextIfOffered() {
                    delegate.setPassword(password)
                    continue
                }
                // Still shut. Whichever way it failed, the answer is the same
                // engine, so the message names it — and `invalidArchive` is what
                // lets automatic mode hand the archive to 7-Zip without asking
                // the user anything again.
                //
                // Only the cause differs, and only sometimes: a password-shaped
                // failure is worth naming an encrypted header for, because XAD
                // reports one as the same decrunch error a damaged archive gets
                // and cannot tell the user which it was.
                let cause = looksLikeAPassword
                    ? "If the archive has an encrypted header, switch"
                    : "Switch"
                throw ArchiveError.invalidArchive(
                    "Could not open \(url.lastPathComponent) with the XAD engine. \(cause) to 7-Zip in Settings \u{2192} Archive Formats, or turn on Automatic engine selection.")
            }

            let handle = XADArchiveWithPasswordSupport(
                url: url, attempts: attempts, delegate: delegate, archive: opened)

            // Listing worked, but the entries are encrypted, so the password is
            // still wanted — and still wanted *now*, because the sidecar fold
            // already happened in the open above. Nobody to ask is not a failure:
            // the names are readable, and that is what a Quick Look preview shows.
            if delegate.currentPassword == nil, handle.hasEncryptedEntry,
               let password = try await attempts.nextIfOffered() {
                delegate.setPassword(password)
                continue
            }
            return handle
        }
    }

    private static func openArchive(
        at url: URL,
        delegate: XADArchiveDelegate
    ) async throws -> (XADArchive?, XADError) {
        // blocking XADMaster call — it parses the whole archive, and for an
        // encrypted one it decrypts every sidecar on the way past
        try await runBlocking {
            // initWithFile:delegate:error: over the plain initWithFile: so a
            // failure carries a code instead of a bare nil, and so the delegate
            // is in place for the parse rather than only afterwards.
            var error: XADError = 0
            let archive = XADArchive(file: url.path, delegate: delegate, error: &error)
            return (archive, error)
        }
    }

    /// Failures that mean "the bytes did not decode" — on an encrypted archive
    /// that is a wrong or missing password far more often than a damaged file.
    /// Deliberately excludes the unambiguous ones (write, open, out of memory,
    /// skip, break) so a real I/O problem still surfaces as itself.
    private static let passwordSuspectErrors: Set<XADError> = [
        XADUnknownError,      // RAR3/4, wrong password
        XADInputError,        // RAR3/4, wrong password mid-stream
        XADIllegalDataError,
        XADNotSupportedError, // RAR, no password set
        XADDecrunchError,     // 7z
        XADChecksumError
    ]

    /// Whether any entry is encrypted. Cached because the answer cannot change
    /// for an open archive, and re-read after every open because the set of
    /// entries can.
    private var hasEncryptedEntry: Bool {
        if let cachedHasEncryptedEntry { return cachedHasEncryptedEntry }
        let count = archive.numberOfEntries()
        let found = (0..<count).contains { archive.entryIsEncrypted($0) }
        cachedHasEncryptedEntry = found
        return found
    }
    private var cachedHasEncryptedEntry: Bool?

    /// Entry numbers by the path the entry has in the archive.
    ///
    /// Extraction addresses entries by path, never by the number a listing
    /// showed earlier: an archive opened under a password that turned out to be
    /// wrong lists the sidecars XADMaster could not fold as entries of their own,
    /// so it has more entries, at different numbers, than the same archive opened
    /// with the right one.
    ///
    /// Built on first use rather than on every open, because listing an archive
    /// never needs it.
    private var indicesByPath: [String: Int32] {
        if let cachedIndicesByPath { return cachedIndicesByPath }
        var map: [String: Int32] = [:]
        for index in 0..<archive.numberOfEntries() {
            guard let path = archive.name(ofEntry: index) else { continue }
            // First wins: a duplicate name is the archive's own problem, and the
            // earlier entry is the one a listing showed.
            if map[path] == nil { map[path] = index }
        }
        cachedIndicesByPath = map
        return map
    }
    private var cachedIndicesByPath: [String: Int32]?

    /// Drops everything the previous open decided. Called when the archive has
    /// been opened again, which can change both the entries and their numbers.
    private func reindex() {
        cachedHasEncryptedEntry = nil
        cachedIndicesByPath = nil
    }

    /// Whether `path` names an AppleDouble sidecar — the hidden companion that
    /// carries a file's Finder tags and resource fork, written either as a
    /// `._name` beside the file or under the `__MACOSX/` mirror.
    ///
    /// These are the only entries that can be in one listing of an archive and
    /// not another: XADMaster folds each one onto the file it describes while
    /// parsing, and can only do that once it can decrypt it.
    private static func isAppleDoubleSidecar(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        if components.first == "__MACOSX" { return true }
        return components.last?.hasPrefix("._") ?? false
    }

    /// Runs `operation` against the open archive, and when it fails for what
    /// looks like a password problem asks for another password and opens the
    /// archive again before retrying.
    ///
    /// Opening again rather than just calling `setPassword`: the fold of a file's
    /// Mac metadata onto it happens during the parse, so an archive opened under
    /// the wrong password has already lost it. Setting the password on that
    /// archive decrypts the contents and nothing else — which is the shape the
    /// bug had before the password moved to the open.
    private func withPasswordRetry<T>(
        _ operation: @escaping (XADArchive, [String: Int32]) -> T
    ) async throws -> T {
        while true {
            let current = archive
            let indices = indicesByPath
            current.clearLastError()

            // blocking XADMaster call — keep it off the cooperative pool
            let value = try await runBlocking { operation(current, indices) }
            // Captured together, before anything else touches the archive: a
            // later call would overwrite XAD's lastError and the throw below
            // could then report the wrong failure.
            let error = current.lastError()
            let errorDescription = current.describeLastError() ?? ""

            if error == 0 { return value }

            // XADMaster only reports XADPasswordError for the formats whose
            // decryptors check the password explicitly — zip, and RAR5 once it
            // gets that far. Everywhere else a wrong password surfaces as
            // whatever the decoder happened to choke on: a decrunch error on 7z,
            // "not fully supported" or an input/unknown error on RAR3/4. So on an
            // archive that has encrypted entries, treat any data-shaped failure
            // as a possible password problem. Real I/O and resource errors are
            // left alone, and the attempt ceiling stops a genuinely broken
            // archive from looping. Same trade the 7-Zip engine makes for 7z AES,
            // which has no password verifier either.
            let isPasswordError = error == XADPasswordError
                || (hasEncryptedEntry && Self.passwordSuspectErrors.contains(error))
            guard isPasswordError else {
                throw ArchiveError.xadError(error, errorDescription)
            }

            delegate.setPassword(try await attempts.next())
            let (reopened, openError) = try await Self.openArchive(at: url, delegate: delegate)
            guard let reopened else {
                throw ArchiveError.extractionFailed(
                    "Could not reopen \(url.lastPathComponent) with the new password (XAD error \(openError))")
            }
            archive = reopened
            reindex()
        }
    }

    /// Reads something the parse already worked out. These cannot fail for a
    /// password: by the time the archive is open its password is settled, and
    /// what they return was decided during that parse.
    private func read<T: Sendable>(_ body: @escaping (XADArchive) -> T) async throws -> T {
        let current = archive
        // blocking XADMaster call — keep it off the cooperative pool
        return try await runBlocking { body(current) }
    }

    func setNameEncoding(_ encoding: UInt) async throws {
        try await read { $0.setNameEncoding(encoding) }
    }

    func numberOfEntries() async throws -> Int32 {
        try await read { $0.numberOfEntries() }
    }

    func name(ofEntry n: Int32) async throws -> String {
        try await read { $0.name(ofEntry: n) ?? "" }
    }

    func entryIsDirectory(_ n: Int32) async throws -> Bool {
        try await read { $0.entryIsDirectory(n) }
    }

    func entryHasSize(_ n: Int32) async throws -> Bool {
        try await read { $0.entryHasSize(n) }
    }

    func entryIsEncrypted(_ n: Int32) async throws -> Bool {
        try await read { $0.entryIsEncrypted(n) }
    }

    func compressedSize(ofEntry n: Int32) async throws -> Int {
        try await read { Int($0.compressedSize(ofEntry: n)) }
    }

    func uncompressedSize(ofEntry n: Int32) async throws -> Int {
        try await read { Int($0.uncompressedSize(ofEntry: n)) }
    }

    func attributes(ofEntry n: Int32) async throws -> [AnyHashable: Any] {
        let current = archive
        // blocking XADMaster call — keep it off the cooperative pool
        let boxed = try await runBlocking { AttributesBox(current.attributes(ofEntry: n) ?? [:]) }
        return boxed.attributes
    }

    /// Extracts the entry at `path`.
    ///
    /// - Returns: whether an entry was extracted. False only for a sidecar the
    ///   archive no longer has: one listed before the password was known is
    ///   folded onto the file it describes once the password is right, and an
    ///   extraction that still names it is asking for something that has become
    ///   part of another file. Any other path the archive does not have is a
    ///   caller asking for an entry that was never there, which is an error.
    @discardableResult
    func extractEntry(path: String, to destination: String) async throws -> Bool {
        guard indicesByPath[path] != nil else {
            guard Self.isAppleDoubleSidecar(path) else {
                throw ArchiveError.extractionFailed(
                    "Could not extract \(path): the archive has no such entry")
            }
            return false
        }

        // The number is looked up from the map the retry hands in, so a reopen's
        // renumbering is picked up on the attempt that follows it.
        let result = try await withPasswordRetry { archive, indices in
            guard let index = indices[path] else { return true }
            return archive.extractEntry(index, to: destination)
        }
        guard result else {
            throw ArchiveError.extractionFailed("Extraction failed for an unknown reason")
        }
        return indicesByPath[path] != nil
    }

    func extract(to destination: String) async throws {
        let result = try await withPasswordRetry { archive, _ in archive.extract(to: destination) }
        if result == false {
            throw ArchiveError.extractionFailed("Extraction failed for an unknown reason")
        }
    }
}

/// Carries XAD's attribute dictionary across the `runBlocking` hop. The values
/// are Foundation objects XADMaster is done with, and only one thread touches
/// them, but the dictionary itself is not `Sendable`.
private struct AttributesBox: @unchecked Sendable {
    let attributes: [AnyHashable: Any]
    init(_ attributes: [AnyHashable: Any]) { self.attributes = attributes }
}

/// Whether `url` really sits inside `directory`.
///
/// Both sides are standardized first, which is what collapses any `..` segments
/// — an entry path like "../../etc/passwd" resolves out of the destination and is
/// then plainly not a descendant. Symlinks are deliberately not resolved: the
/// candidate is built by appending to `directory`, so both share the same symlink
/// state, and resolving a path that does not exist yet would only desynchronise
/// them (`/var` vs `/private/var`).
private func isContained(_ url: URL, in directory: URL) -> Bool {
    let base = directory.standardizedFileURL.path
    let target = url.standardizedFileURL.path
    let prefix = base.hasSuffix("/") ? base : base + "/"
    return target != base && target.hasPrefix(prefix)
}

final actor ArchiveXadEngine: ArchiveEngine {
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

    /// Opens `url` the one way this engine opens anything: with the password
    /// resolved up front when the archive wants one.
    private func open(
        url: URL,
        passwordResolver: @escaping ArchivePasswordResolver,
        delegate: XADArchiveDelegate
    ) async throws -> XADArchiveWithPasswordSupport {
        let archive = try await XADArchiveWithPasswordSupport.open(
            url: url,
            attempts: ArchivePasswordAttempts(url: url, resolver: passwordResolver),
            delegate: delegate
        )
        try await archive.setNameEncoding(NSUTF8StringEncoding)
        return archive
    }

    func loadArchive(
        url: URL,
        passwordResolver: @escaping ArchivePasswordResolver
    ) async throws -> ArchiveEngineLoadResult {
        let archive = try await open(
            url: url, passwordResolver: passwordResolver, delegate: XADArchiveDelegate())

        var entries: [UUID: ArchiveItem] = [:]
        var uncompressedSizeOverall: Int64 = 0
        var isEncrypted = false
        let numberOfEntries = try await archive.numberOfEntries()
        for index in 0..<numberOfEntries {
            // name
            let path = try await archive.name(ofEntry: index)
            let isDir = try await archive.entryIsDirectory(index)
            if try await archive.entryIsEncrypted(index) { isEncrypted = true }

            // tar archives (and similar) don't have a compressed size as they
            // just package up files.
            var compressedSize: Int = -1
            var uncompressedSize: Int = -1
            compressedSize = try await archive.compressedSize(ofEntry: index)
            if !isDir {
                if try await archive.entryHasSize(index) {
                    uncompressedSize = try await archive.uncompressedSize(ofEntry: index)
                } else {
                    uncompressedSize = try await archive.compressedSize(ofEntry: index)
                }
            }

            // get more attributes
            var modificationDate: Date?
            var posixPermissions: Int?
            let attributes = try await archive.attributes(ofEntry: index)
            if let dict = attributes as? [String: Any] {
                modificationDate = dict["NSFileModificationDate"] as? Date
                posixPermissions = dict["NSFilePosixPermissions"] as? Int
            }

            var name = path
            let parts = path.split(separator: "/")
            if let last = parts.last {
                name = String(last)
            }

            let entry = ArchiveItem(
                index: UInt32(index),
                name: name,
                virtualPath: path, // the name in the archive dictionary is usually the full path
                type: isDir ? .directory : .file,
                compressedSize: Int(compressedSize),
                uncompressedSize: Int(uncompressedSize),
                modificationDate: modificationDate,
                posixPermissions: posixPermissions
            )

            entries[entry.id] = entry

            // Directory entries keep the "-1" unknown sentinel in
            // `uncompressedSize` (their size block is skipped under `if !isDir`
            // above), so clamp before accumulating — otherwise every directory
            // subtracts a byte from the reported total. Mirrors the same
            // `max(0, …)` clamp the extraction side applies for its byte totals.
            uncompressedSizeOverall += Int64(Swift.max(0, entry.uncompressedSize))
        }

        emit(.done)

        return ArchiveEngineLoadResult(
            items: entries,
            hasTree: false,
            uncompressedSize: uncompressedSizeOverall,
            // A header-encrypted archive needed the password just to list, so
            // it counts as encrypted even if no entry flags itself.
            isEncrypted: isEncrypted || archive.wasOpenedWithAPassword
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
        let totalBytes = items.reduce(Int64(0)) { $0 + Int64(Swift.max(0, $1.uncompressedSize)) }
        let delegate = XADArchiveDelegate(
            onProgress: onProgress, totalBytes: totalBytes, usesGlobalCounters: false)
        let archive = try await open(
            url: url, passwordResolver: passwordResolver, delegate: delegate)

        var urlsByItemID: [UUID: URL] = [:]

        // Directories that were already on disk before any of this ran, with the
        // date they had. A directory sitting there belongs to whoever put it
        // there — the destination is not always empty — and its date is not ours
        // to rewrite.
        //
        // Taken up front rather than as each entry is reached, because entry order
        // is not defined: a directory this extraction creates as the parent of an
        // earlier file would otherwise look pre-existing by the time its own entry
        // came round, and lose the date it should have had.
        var preexistingDirectoryDates: [UUID: Date] = [:]
        var entriesToCreate: Set<UUID> = []
        for item in items {
            guard let virtualPath = item.virtualPath else { continue }
            let url = destination.appendingPathComponent(virtualPath)
            let existing = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate

            if existing == nil {
                // Nothing there yet, so this extraction brings it into being — and
                // that is what moves the date of the directory holding it.
                entriesToCreate.insert(item.id)
            } else if item.type == .directory, let existing {
                preexistingDirectoryDates[item.id] = existing
            }
        }

        // Parents before their contents. Entry order otherwise comes out of a
        // dictionary and is not defined, so whether a directory ended up with the
        // date of the files written into it was a coin toss.
        let ordered = items.sorted { ($0.virtualPath ?? "") < ($1.virtualPath ?? "") }

        for item in ordered {
            try Task.checkCancellation()
            guard let virtualPath = item.virtualPath else {
                throw ArchiveError.extractionFailed("Could not extract file: missing virtual path")
            }

            let resultUrl = destination.appendingPathComponent(virtualPath, isDirectory: item.type == .directory)

            let extracted: Bool
            do {
                extracted = try await archive.extractEntry(path: virtualPath, to: destination.path)
            } catch {
                // XAD creates the output file before it decodes, so a failure
                // (wrong password, corrupt data) leaves a truncated or empty
                // file that looks like a successful extraction. Remove it — but
                // only if it is actually inside the destination. `virtualPath`
                // comes from the archive, so an entry named "../something" would
                // otherwise aim this delete at a file the user never asked us to
                // touch, and a wrong password is enough to trigger it.
                if isContained(resultUrl, in: destination) {
                    try? FileManager.default.removeItem(at: resultUrl)
                }
                // a should-stop answer makes XAD fail the entry — surface
                // it as cancellation, not as an extraction error
                if delegate.wasStopped {
                    throw CancellationError()
                }
                throw error
            }
            if delegate.wasStopped {
                throw CancellationError()
            }
            delegate.advanceBase(by: Int64(Swift.max(0, item.uncompressedSize)))

            // An entry the archive no longer has is one whose sidecar has been
            // folded onto the file it describes — nothing to report a URL for.
            if extracted { urlsByItemID[item.id] = resultUrl }
        }

        restoreDirectoryDates(for: items, at: urlsByItemID,
                              preexisting: preexistingDirectoryDates,
                              creating: entriesToCreate)

        return ArchiveExtractionResult(urlsByItemID: urlsByItemID)
    }

    /// Stamps extracted directories with the date the archive gave them.
    ///
    /// XADMaster restores dates for files but leaves directories carrying the
    /// moment of extraction — every other tool on the platform (`ditto`, `unzip`,
    /// `tar`, Keka, The Unarchiver) puts the original back, so the gap is ours to
    /// close rather than something to match.
    ///
    /// It runs after every entry has landed, and it has to: writing a file into a
    /// directory sets that directory's modification time again, so a date applied
    /// while the extraction was still going would not have survived its own
    /// contents.
    /// Whether this extraction creates an entry *directly* inside `directory`,
    /// which is the only thing that moves that directory's own date.
    ///
    /// Not "somewhere below": adding a file to `a/b` moves `b` and leaves `a`
    /// exactly as it was. And not merely "an entry names this directory": an entry
    /// that was already on disk is rewritten in place, which the directory holding
    /// it never notices.
    private func extractionCreatesEntry(
        directlyIn directory: ArchiveItem,
        among items: [ArchiveItem],
        creating: Set<UUID>
    ) -> Bool {
        guard let path = directory.virtualPath else { return false }
        let prefix = path.hasSuffix("/") ? path : path + "/"
        return items.contains { other in
            guard other.id != directory.id, creating.contains(other.id),
                  let otherPath = other.virtualPath, otherPath.hasPrefix(prefix)
            else { return false }
            return !otherPath.dropFirst(prefix.count).contains("/")
        }
    }

    private func restoreDirectoryDates(
        for items: [ArchiveItem],
        at urls: [UUID: URL],
        preexisting: [UUID: Date],
        creating: Set<UUID>
    ) {
        for item in items where item.type == .directory {
            guard let date = item.modificationDate, let url = urls[item.id] else { continue }

            guard let existingDate = preexisting[item.id] else {
                // Ours to stamp: this extraction made the directory.
                try? FileManager.default.setAttributes([.modificationDate: date],
                                                       ofItemAtPath: url.path)
                continue
            }

            // Not ours. XADMaster stamps a directory with the archive's date on
            // its way past whether or not it created it, and it is vendored, so
            // the only place to undo that is here.
            //
            // Whether it needs undoing is decided by what this extraction wrote,
            // not by comparing dates: a folder that received files has moved on
            // for a real reason and every tool on the platform would have moved it
            // the same way, while a folder that received nothing should read
            // exactly as it did before. Proximity cannot tell those apart — an
            // archive made moments ago carries dates a legitimate write is
            // indistinguishable from.
            guard !extractionCreatesEntry(directlyIn: item, among: items, creating: creating)
            else { continue }
            try? FileManager.default.setAttributes([.modificationDate: existingDate],
                                                   ofItemAtPath: url.path)
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
        // whole-archive mode: XAD reports its own global byte counters
        let delegate = XADArchiveDelegate(
            onProgress: onProgress, totalBytes: 0, usesGlobalCounters: true)
        let archive = try await open(
            url: url, passwordResolver: passwordResolver, delegate: delegate)

        do {
            try await archive.extract(to: destination.path)
        } catch {
            if delegate.wasStopped {
                throw CancellationError()
            }
            throw error
        }
        if delegate.wasStopped {
            throw CancellationError()
        }
    }
}
