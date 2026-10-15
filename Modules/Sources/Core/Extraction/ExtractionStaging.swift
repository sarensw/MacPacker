//
//  ExtractionStaging.swift
//  Modules
//
//  Where a whole-archive extraction writes until it has succeeded.
//

import Foundation
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "extraction")

/// A work folder inside the destination that an extraction writes into, so
/// that a run which does not finish leaves the destination as it found it.
///
/// The engines write to disk as they go, and none of them takes back what it
/// wrote when it is cancelled or meets a damaged entry. Handing them the
/// destination itself therefore left half an archive there, looking like a
/// whole one. Handing them this folder instead keeps every such run inside it:
/// `discard()` removes the folder and nothing else was touched, `commit(as:)`
/// moves the result out once the engine is done.
///
/// The folder sits *inside* the destination rather than in the cache folder
/// "Extract selected" goes through, for two reasons. It is on the destination's
/// volume, so putting the result in place is a rename — no second copy of a
/// large archive, and no room needed on the startup disk for one headed
/// elsewhere. And the grant that lets the app write the destination already
/// covers it, so the sandbox needs nothing new.
///
/// It is not hidden: it carries the archive's name and an extension of its own,
/// which the app declares as a package type — so Finder shows one item where the
/// result is going to be, not a folder of half-written files to wander into.
/// Finder shows that item dimmed, as it shows one it is still copying itself
/// (see `busyDate`), and `ExtractionFinderProgress` puts the run's progress on
/// it. Should the app ever die mid-run, what stays behind is in plain sight
/// under a name that says what it is.
struct ExtractionStaging: Sendable {
    /// The folder to hand to the engine in place of the destination.
    let workFolder: URL
    private let destination: URL
    /// Whether the destination was missing and came into being with the work
    /// folder — the engines create it as well. Then it goes with a discarded
    /// run too.
    private let createdDestination: Bool

    /// When the work folder really came into being — what it is given back as
    /// its creation date if it becomes the result.
    private let createdAt: Date

    /// The extension of the work folder. The app's Info.plist exports a package
    /// type for it (`com.sarensx.MacPacker.extraction-in-progress`), and the two
    /// have to agree.
    static let workFolderExtension = "macpack"

    /// The creation date by which Finder knows an item is not finished:
    /// 24 January 1984, 08:00 UTC. Finder gives it to what it is copying, and
    /// shows any item that has it dimmed and will not open it — which is what
    /// the work folder is, for as long as it exists.
    static let busyDate = Date(timeIntervalSince1970: 443_779_200)

    /// Creates the work folder in `destination`.
    ///
    /// - Parameter name: What the work folder is called, before its extension:
    ///   the archive's name without its own, so the item in Finder reads as
    ///   that archive being extracted.
    init(in destination: URL, named name: String) throws {
        let fm = FileManager.default
        self.destination = destination
        self.createdDestination = !fm.fileExists(atPath: destination.path)
        self.createdAt = Date()
        do {
            if createdDestination {
                try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            }
            self.workFolder = try Self.makeWorkFolder(in: destination, named: name)
        } catch {
            // The system's own message would name the work folder, which
            // nobody asked to write.
            log.error("Could not create the extraction work folder", context: [
                "destination": destination.path, "error": error.localizedDescription,
            ])
            throw ArchiveError.extractionFailed(
                "Could not write to the folder \"\(destination.lastPathComponent)\".")
        }
        // Not every volume keeps a creation date. Where it does not take, the
        // item is merely not dimmed.
        Self.setCreationDate(Self.busyDate, of: workFolder)
        Self.note(workFolder)
    }

    /// Creates `<name>.macpack` in `destination`, or `<name> (2).macpack`, … when
    /// that is taken — by a second run of the same archive, or by what a crash
    /// left there. Created, not just named: of two runs that start together,
    /// only one gets a given folder.
    private static func makeWorkFolder(in destination: URL, named name: String) throws -> URL {
        // Room for a counter and the extension within what a file name may
        // have: 255 UTF-16 units, counted in the decomposed form file urls
        // carry names in.
        var base = name.isEmpty ? "Archive" : name
        while base.decomposedStringWithCanonicalMapping.utf16.count > 240 {
            base.removeLast()
        }
        var counter = 1
        while true {
            let candidate = destination.appendingPathComponent(
                (counter == 1 ? base : "\(base) (\(counter))") + "." + workFolderExtension,
                isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: false)
                return candidate
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                counter += 1
            }
        }
    }

    /// Puts what the engine extracted where the user asked for it, and removes
    /// the work folder.
    ///
    /// Into the destination itself, the result lands the way the engines put it
    /// there when they wrote to it directly: a folder that is already there is
    /// extracted into, a file that is already there is replaced, and a link
    /// stands for what it points to. What could not be done that way — a file
    /// where a folder goes, a file or folder that cannot be written — is found
    /// *before* anything moves, and throws with the destination untouched.
    ///
    /// What cannot be foreseen — a file protected against deletion, a disk that
    /// gives out — stops the commit part-way. Then every step already taken is
    /// taken back: a commit puts all of the result in place, or leaves the
    /// destination as it was.
    ///
    /// - Parameter container: The folder the result is to become: smart
    ///   extraction's container, which must not exist yet. `nil` puts the
    ///   extracted items straight into the destination.
    func commit(as container: URL? = nil) throws {
        let fm = FileManager.default
        // The run is over, whichever way this ends: a commit that throws is
        // followed by `discard()`.
        defer { Self.unnote(workFolder) }
        if let container {
            // It is the result now, and no longer to be shown as unfinished.
            Self.setCreationDate(createdAt, of: workFolder)
            // The whole result in one rename. Same parent, so even a tree of
            // read-only folders moves — nothing inside it changes.
            try fm.moveItem(at: workFolder, to: container)
            return
        }

        var steps: [Step] = []
        for name in try fm.contentsOfDirectory(atPath: workFolder.path).sorted() {
            try Self.plan(
                workFolder.appendingPathComponent(name),
                onto: destination.appendingPathComponent(name),
                into: &steps)
        }
        var taken: [Taken] = []
        do {
            for step in steps {
                taken.append(try step.run())
            }
        } catch {
            for step in taken.reversed() {
                step.undo()
            }
            throw error
        }
        // Nothing can fail any more: what was kept for an undo can go.
        for step in taken {
            step.settle()
        }
        // What is left are the folders that were merged away, emptied.
        Self.removeTree(workFolder)
    }

    /// Removes the work folder and everything in it: the destination is as it
    /// was before the run.
    func discard() {
        Self.removeTree(workFolder)
        Self.unnote(workFolder)
        if createdDestination {
            // only goes when empty — whatever else got there is not ours
            _ = rmdir(destination.path)
        }
    }

    // MARK: - After a crash

    /// Where the work folders in use are noted: by the name of each, with a
    /// bookmark of the folder it is in — the access needed to remove it at
    /// the next start, should the app stop mid-run and leave it behind — and
    /// the start of the app that writes it, whose own are never taken for
    /// leftovers.
    static let ledgerKey = "extractionWorkFolders"
    private static let ledgerLock = NSLock()

    /// This start of the app, as its notes name it. Not the process id, which
    /// a later start can be given again.
    static let thisStart = UUID().uuidString

    /// Notes `workFolder` as in use by `start` — this one, unless a test says.
    static func note(_ workFolder: URL, in store: UserDefaults = .standard, by start: String = thisStart) {
        let folder = workFolder.deletingLastPathComponent()
        guard let bookmark = (try? folder.bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil))
            ?? (try? folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)) else {
            log.error("Could not note the extraction work folder", context: ["folder": workFolder.path])
            return
        }
        ledgerLock.withLock {
            var noted = store.dictionary(forKey: ledgerKey) as? [String: [String: Any]] ?? [:]
            noted[workFolder.path] = ["in": bookmark, "name": workFolder.lastPathComponent, "by": start]
            store.set(noted, forKey: ledgerKey)
        }
    }

    /// Takes the note away: the run is over, whichever way it ended.
    static func unnote(_ workFolder: URL, in store: UserDefaults = .standard) {
        ledgerLock.withLock {
            var noted = store.dictionary(forKey: ledgerKey) as? [String: [String: Any]] ?? [:]
            guard noted.removeValue(forKey: workFolder.path) != nil else { return }
            store.set(noted, forKey: ledgerKey)
        }
    }

    /// Removes the work folders that runs of an earlier start of the app left
    /// behind: it stopped before they were done, so they are still noted. For
    /// the app to call as it starts. What this start is writing already — a
    /// Finder action can come in first — is its own, and left alone.
    ///
    /// Only what is still a work folder goes: a folder with this extension
    /// that Finder still shows as being written (`busyDate`), which nothing
    /// else gives one — and never one in the Trash. A note whose folder is
    /// gone, or no longer that, is simply dropped.
    static func removeLeftovers(in store: UserDefaults = .standard) {
        let noted = ledgerLock.withLock {
            store.dictionary(forKey: ledgerKey) as? [String: [String: Any]] ?? [:]
        }
        for (path, entry) in noted where entry["by"] as? String != thisStart {
            defer { unnote(URL(fileURLWithPath: path), in: store) }
            guard let bookmark = entry["in"] as? Data, let name = entry["name"] as? String else { continue }
            // a volume that is not there is not asked for
            var stale = false
            guard let folder = (try? URL(
                resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutMounting],
                relativeTo: nil, bookmarkDataIsStale: &stale))
                ?? (try? URL(resolvingBookmarkData: bookmark, options: [.withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale))
            else { continue }
            let scoped = folder.startAccessingSecurityScopedResource()
            defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

            let leftover = folder.appendingPathComponent(name, isDirectory: true)
            guard isLeftover(leftover) else { continue }
            removeTree(leftover)
            log.notice("Removed what an extraction left when the app stopped", context: ["folder": leftover.path])
        }
    }

    /// Whether `url` is still an unfinished work folder.
    static func isLeftover(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        guard url.pathExtension == workFolderExtension,
              !path.contains("/.Trash/"), !path.contains("/.Trashes/"),
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .creationDateKey]),
              values.isDirectory == true, values.isSymbolicLink != true
        else { return false }
        return values.creationDate == busyDate
    }

    // MARK: - Putting the result in place

    /// A step that has been taken.
    private struct Taken {
        /// Takes the step back: the destination is as it was before it.
        let undo: () -> Void
        /// What is left to do once every step has been taken.
        let settle: () -> Void
    }

    private enum Step {
        /// Nothing is in the way: the item moves as it is, whatever is in it.
        case move(URL, to: URL)
        /// A file is in the way: the item takes its place.
        case replace(URL, with: URL)

        func run() throws -> Taken {
            switch self {
            case .move(let source, let target):
                do {
                    try ExtractionStaging.move(source, to: target)
                } catch {
                    // nothing was there before, so nothing of a move that
                    // stopped half-way may stay
                    ExtractionStaging.removeTree(target)
                    throw error
                }
                return Taken(
                    // back where it came from, where a discarded run takes it along
                    undo: {
                        do {
                            try ExtractionStaging.move(target, to: source)
                        } catch {
                            ExtractionStaging.removeTree(target)
                        }
                    },
                    settle: {})
            case .replace(let target, with: let source):
                // through a link, as the engines write through one
                let real = target.resolvingSymlinksInPath()
                // Where the volume can do it, the two files change places in
                // one go: the new one is in place, and the old one waits in the
                // work folder — for an undo, or to go with that folder.
                if renamex_np(source.path, real.path, UInt32(RENAME_SWAP)) == 0 {
                    return Taken(
                        undo: {
                            if renamex_np(source.path, real.path, UInt32(RENAME_SWAP)) != 0 {
                                log.error("Could not put a replaced file back", context: [
                                    "file": real.path, "errno": "\(errno)",
                                ])
                            }
                        },
                        settle: {})
                }
                let reason = errno
                guard [ENOTSUP, EINVAL, EXDEV].contains(reason) else {
                    // not a matter of how, then: the file is not to be touched
                    throw ArchiveError.extractionFailed(
                        "Could not replace \"\(real.lastPathComponent)\": the file in the destination cannot be changed.")
                }
                // No changing places on this volume, or the file is on another
                // one, behind a link. Then the file that is there is kept
                // beside itself until every step has been taken.
                let kept = try ExtractionStaging.keep(real)
                do {
                    if rename(source.path, real.path) != 0 {
                        // behind a link the file may be on another volume,
                        // where there is no renaming onto it
                        try ExtractionStaging.replace(real, withCopyOf: source)
                    }
                } catch {
                    ExtractionStaging.putBack(kept, as: real)
                    throw error
                }
                return Taken(
                    undo: { ExtractionStaging.putBack(kept, as: real) },
                    settle: { try? FileManager.default.removeItem(at: kept) })
            }
        }
    }

    /// Moves an extracted item to where nothing is.
    ///
    /// A folder moving to another parent gets its `..` rewritten, which takes
    /// write permission on the folder itself — and an archive may hold one
    /// without it. It is given that permission for the move alone.
    private static func move(_ source: URL, to target: URL) throws {
        let fm = FileManager.default
        do {
            try fm.moveItem(at: source, to: target)
        } catch {
            guard let mode = mode(ofFolder: source), mode & 0o200 == 0 else { throw error }
            try fm.setAttributes([.posixPermissions: mode | 0o200], ofItemAtPath: source.path)
            do {
                try fm.moveItem(at: source, to: target)
            } catch {
                try? fm.setAttributes([.posixPermissions: mode], ofItemAtPath: source.path)
                throw error
            }
            try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: target.path)
        }
    }

    /// Keeps the file at `real` under a second, hidden name beside it, and
    /// returns that name.
    ///
    /// As a hard link where the volume has them: the file then stays in place
    /// under its own name too, and replacing it remains the single rename it
    /// was. Where the volume has none, the file itself is moved aside.
    static func keep(_ real: URL) throws -> URL {
        let kept = real.deletingLastPathComponent().appendingPathComponent(
            ".macpacker-" + UUID().uuidString.prefix(8).lowercased())
        if link(real.path, kept.path) != 0, rename(real.path, kept.path) != 0 {
            throw ArchiveError.extractionFailed(
                "Could not replace \"\(real.lastPathComponent)\": the file in the destination cannot be changed.")
        }
        return kept
    }

    /// Puts a kept file back under its own name, whatever is there now.
    static func putBack(_ kept: URL, as real: URL) {
        if rename(kept.path, real.path) != 0 {
            log.error("Could not put a replaced file back", context: [
                "file": real.path, "kept": kept.path, "errno": "\(errno)",
            ])
            return
        }
        // A rename between two names of one and the same file changes nothing:
        // then the second name is what is left over.
        if unlink(kept.path) != 0, errno != ENOENT {
            log.error("Could not remove the second name of a kept file", context: [
                "kept": kept.path, "errno": "\(errno)",
            ])
        }
    }

    /// Replaces `real` with `source` where the one cannot simply be renamed
    /// onto the other. The new file is copied beside the old one first, on the
    /// old one's volume, and takes its place in a single rename: the old file
    /// goes only once the new one is whole. A copy that fails — a full disk is
    /// enough — leaves the old file as it was.
    static func replace(_ real: URL, withCopyOf source: URL) throws {
        let fm = FileManager.default
        let beside = real.deletingLastPathComponent().appendingPathComponent(
            ".macpacker-" + UUID().uuidString.prefix(8).lowercased())
        do {
            try fm.copyItem(at: source, to: beside)
            if rename(beside.path, real.path) != 0 {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? fm.removeItem(at: beside)
            throw error
        }
        // the work folder goes anyway; this only keeps it from holding a second copy
        try? fm.removeItem(at: source)
    }

    /// Works out how `source` — one extracted item — gets to `target`, without
    /// touching the destination.
    private static func plan(_ source: URL, onto target: URL, into steps: inout [Step]) throws {
        let fm = FileManager.default
        let name = target.lastPathComponent

        // `fileExists` follows links, as the engines' own writes do.
        var targetIsFolder: ObjCBool = false
        guard fm.fileExists(atPath: target.path, isDirectory: &targetIsFolder) else {
            // A link that points nowhere is not "nothing there": it is in the
            // way, and not ours to remove.
            guard (try? fm.attributesOfItem(atPath: target.path)) == nil else {
                throw ArchiveError.extractionFailed(
                    "Could not extract \"\(name)\": the destination holds a broken link of that name.")
            }
            steps.append(.move(source, to: target))
            return
        }

        let sourceMode = mode(ofFolder: source)
        switch (sourceMode != nil, targetIsFolder.boolValue) {
        case (true, true):
            guard fm.isWritableFile(atPath: target.path) else {
                throw ArchiveError.extractionFailed(
                    "Could not extract into \"\(name)\": the folder in the destination cannot be written.")
            }
            // The extracted folder is merged away: it has to let its content
            // be listed and moved out, which the permissions the archive gave
            // it may not allow. It is ours, and gone after the merge.
            if let sourceMode, sourceMode & 0o700 != 0o700 {
                try fm.setAttributes([.posixPermissions: sourceMode | 0o700], ofItemAtPath: source.path)
            }
            for child in try fm.contentsOfDirectory(atPath: source.path).sorted() {
                try plan(
                    source.appendingPathComponent(child),
                    onto: target.appendingPathComponent(child),
                    into: &steps)
            }
        case (false, false):
            guard fm.isWritableFile(atPath: target.path) else {
                throw ArchiveError.extractionFailed(
                    "Could not replace \"\(name)\": the file in the destination cannot be written.")
            }
            steps.append(.replace(target, with: source))
        case (true, false):
            throw ArchiveError.extractionFailed(
                "Could not extract the folder \"\(name)\": the destination holds a file of that name.")
        case (false, true):
            throw ArchiveError.extractionFailed(
                "Could not extract the file \"\(name)\": the destination holds a folder of that name.")
        }
    }

    private static func setCreationDate(_ date: Date, of folder: URL) {
        var url = folder
        var values = URLResourceValues()
        values.creationDate = date
        do {
            try url.setResourceValues(values)
        } catch {
            log.error("Could not set the work folder's creation date", context: [
                "folder": folder.path, "error": error.localizedDescription,
            ])
        }
    }

    /// The permissions of `url` if it is a folder itself — not a link to one,
    /// which moves as the link it is.
    private static func mode(ofFolder url: URL) -> Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeDirectory else { return nil }
        return (attributes[.posixPermissions] as? NSNumber)?.intValue
    }

    /// Removes `folder` and all in it, read-only folders included: an engine
    /// gives folders the permissions the archive holds, and one that may not be
    /// written does not let go of its content.
    static func removeTree(_ folder: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.path) else { return }
        do {
            try fm.removeItem(at: folder)
            return
        } catch {
            // most likely a folder in it that may not be written: see below
        }

        var folders = [folder]
        while let next = folders.popLast() {
            guard let mode = mode(ofFolder: next) else { continue }
            if mode & 0o700 != 0o700 {
                try? fm.setAttributes([.posixPermissions: mode | 0o700], ofItemAtPath: next.path)
            }
            for child in (try? fm.contentsOfDirectory(atPath: next.path)) ?? [] {
                folders.append(next.appendingPathComponent(child))
            }
        }
        do {
            try fm.removeItem(at: folder)
        } catch {
            log.error("Could not remove the extraction work folder", context: [
                "folder": folder.path, "error": error.localizedDescription,
            ])
        }
    }
}

/// What an extraction leaves behind when the app stops in the middle of it.
public enum ExtractionLeftovers {
    /// Removes the work folders that extractions of an earlier start of the
    /// app were writing when it stopped. See `ExtractionStaging.removeLeftovers`.
    public static func removeFromEarlierRuns() {
        ExtractionStaging.removeLeftovers()
    }
}

/// Shows a running extraction on its work folder in Finder: for as long as this
/// is published, Finder draws a progress indicator on the item.
///
/// It is the system's own mechanism — a file `Progress`, published for the
/// item's url — and Finder is merely the subscriber everyone has open. Nothing
/// is shown by this app, and nothing happens if nobody is looking.
final class ExtractionFinderProgress: @unchecked Sendable {
    // `Progress` is safe to update from any thread; the lock is for `ended`.
    private let progress: Progress
    private let throttle = ProgressThrottle()
    private let lock = NSLock()
    private var ended = false

    /// - Parameter totalBytes: What the archive unpacks to, when the listing
    ///   says. Until an engine reports a total, the indicator is indeterminate
    ///   without it.
    init(on workFolder: URL, totalBytes: Int64?) {
        progress = Progress(totalUnitCount: totalBytes ?? -1)
        progress.kind = .file
        progress.setUserInfoObject(workFolder, forKey: .fileURLKey)
        progress.setUserInfoObject(
            Progress.FileOperationKind.decompressingAfterDownloading, forKey: .fileOperationKindKey)
        // Stopping a run belongs to the progress window, which knows what to
        // clean up; an indicator that offers it and does nothing would be worse
        // than one that does not offer it.
        progress.isCancellable = false
        progress.isPausable = false
        progress.publish()
    }

    /// How much of the run is done, [0, 1] — `nil` while that is not known.
    var fractionCompleted: Double? {
        progress.isIndeterminate ? nil : progress.fractionCompleted
    }

    /// Whether the indicator is still up.
    var isPublished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !ended
    }

    /// Takes an engine's byte counts. Called from the extraction thread, as
    /// often as the engine pleases — so it is throttled like the progress
    /// window's updates are.
    func report(completed: Int64, total: Int64) {
        guard total > 0, throttle.shouldEmit(at: Date()) else { return }
        progress.totalUnitCount = total
        progress.completedUnitCount = min(max(completed, 0), total)
    }

    /// Takes the indicator down. To be called before the work folder is moved
    /// or removed: the indicator is tied to the item at that url. Safe to call
    /// more than once.
    func end() {
        lock.lock()
        let wasUp = !ended
        ended = true
        lock.unlock()
        if wasUp {
            progress.unpublish()
        }
    }

    deinit {
        end()
    }
}
