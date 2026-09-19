//
//  DropCompressor.swift
//  Modules
//
//  One drop → one archive: the sandbox grant, the destination name, and the
//  headless `ArchiveState` that writes it — the same create/add/save path the
//  Finder "Compress to …" action uses (`AppUrlCompressHandler`). In Core, with
//  the folder-access prompt handed in, so it can be tested without the app.
//

import Combine
import Foundation
import Swift7zip
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "dropwindow")

/// One compress job. The row observes `state.progress` directly rather than
/// having it mirrored here.
@MainActor
public final class DropJob: ObservableObject, Identifiable {
    public enum Outcome: Equatable {
        case running
        case done(URL)
        case failed(String)
        /// Declined the folder-access panel — not an error; nothing was written.
        case denied
    }

    public let id = UUID()
    /// Known before the write starts, so the row has a name from the first frame.
    public let name: String
    /// Published by the writer; the row shows it as a progress bar.
    public let state: ArchiveState
    /// Set through `DropCompressor.finish` — assigning it here publishes on the
    /// job, which redraws its own row but does not tell the list to re-filter.
    @Published public fileprivate(set) var outcome: Outcome = .running
    /// The write itself, for whoever needs to wait for it.
    var task: Task<Void, Never>?

    /// Whether it produced an archive. Used to decide what is worth showing.
    public var succeeded: Bool { if case .done = outcome { true } else { false } }

    init(name: String, state: ArchiveState) {
        self.name = name
        self.state = state
    }
}

@MainActor
public final class DropCompressor: ObservableObject {
    /// Oldest first. Owned here rather than by the view, so a compress started
    /// without the UI (`-AddFiles`) shows up too and closing the window keeps it.
    @Published public private(set) var jobs: [DropJob] = []

    /// Finished rows pile up otherwise — the window is small and the last few
    /// results are the only ones anybody looks at.
    private let maxJobs = 4

    private let catalog: ArchiveTypeCatalog
    private let engineSelector: ArchiveEngineSelectorProtocol
    /// Asks for access to the folder a file is in: the app's powerbox panel.
    private let folderAccess: ArchiveFolderAccessUserProvider

    public init(
        catalog: ArchiveTypeCatalog,
        engineSelector: ArchiveEngineSelectorProtocol,
        folderAccess: @escaping ArchiveFolderAccessUserProvider
    ) {
        self.catalog = catalog
        self.engineSelector = engineSelector
        self.folderAccess = folderAccess
    }

    /// Compresses `files` into one archive next to them.
    ///
    /// The drop grants read access to the items but not to their folder, and
    /// writing needs that — a panel the first time only, since the app's
    /// `FolderAccessStore` reuses a bookmark on any ancestor and Downloads is
    /// entitled. Mixed selections land next to the first item, and the grant
    /// follows it.
    @discardableResult
    public func compress(files: [URL], options: CompressionOptions) -> DropJob? {
        guard let first = files.first else { return nil }
        let folder = first.deletingLastPathComponent()
        let name = CompressDestination.name(files: files, target: folder, ext: options.format.rawValue)

        let state = ArchiveState(catalog: catalog, engineSelector: engineSelector)
        // a save that hits a permission error retries once through this
        state.folderAccessProvider = folderAccess
        let job = DropJob(name: name, state: state)
        jobs.append(job)
        if jobs.count > maxJobs { jobs.removeFirst(jobs.count - maxJobs) }

        log.info("Drop compress starting", context: [
            "files": "\(files.count)",
            "format": options.format.rawValue,
            "level": "\(options.level)"
        ])

        job.task = Task {
            guard await folderAccess(first) else {
                log.notice("Drop compress cancelled — folder access declined")
                finish(job, .denied)
                return
            }

            // after the grant: the panel may have been up a while
            let destination = CompressDestination.unique(named: name, in: folder)

            state.create()
            for file in files {
                state.add(url: file)
            }
            await state.save(to: destination, options: options)?.value

            if let error = state.error {
                log.error("Drop compress failed", context: ["error": error])
                finish(job, .failed(error))
            } else {
                // what the save reopened: the first volume, when it was split —
                // then there is no file at `destination` for Finder to show
                let written = state.url ?? destination
                log.info("Drop compress finished", context: ["file": written.lastPathComponent])
                finish(job, .done(written))
            }
        }

        return job
    }

    /// A job's own `@Published` reaches its row but not the view that decides which
    /// rows to show, so the compressor republishes too — otherwise a finished
    /// archive keeps its row forever.
    private func finish(_ job: DropJob, _ outcome: DropJob.Outcome) {
        objectWillChange.send()
        job.outcome = outcome
    }
}
