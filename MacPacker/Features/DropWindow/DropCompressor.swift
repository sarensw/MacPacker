//
//  DropCompressor.swift
//  MacPacker
//
//  One drop → one archive: the sandbox grant, the destination name, and the
//  headless `ArchiveState` that writes it — the same create/add/save path the
//  Finder "Compress to …" action uses (`AppUrlCompressHandler`).
//

import AppKit
import Core
import Foundation
import Swift7zip
import tb

private let log = tb.Logger(subsystem: "app.MacPacker", category: "dropwindow")

/// One compress job. The row observes `state.progress` directly rather than
/// having it mirrored here.
@MainActor
final class DropJob: ObservableObject, Identifiable {
    enum Outcome: Equatable {
        case running
        case done(URL)
        case failed(String)
        /// Declined the folder-access panel — not an error; nothing was written.
        case denied
    }

    let id = UUID()
    /// Known before the write starts, so the row has a name from the first frame.
    let name: String
    /// Published by the writer; the row shows it as a progress bar.
    let state: ArchiveState
    /// Set through `DropCompressor.finish` — assigning it here publishes on the
    /// job, which redraws its own row but does not tell the list to re-filter.
    @Published fileprivate(set) var outcome: Outcome = .running

    /// Whether it produced an archive. Used to decide what is worth showing.
    var succeeded: Bool { if case .done = outcome { true } else { false } }

    init(name: String, state: ArchiveState) {
        self.name = name
        self.state = state
    }
}

@MainActor
final class DropCompressor: ObservableObject {
    /// Oldest first. Owned here rather than by the view, so a compress started
    /// without the UI (`-AddFiles`) shows up too and closing the window keeps it.
    @Published private(set) var jobs: [DropJob] = []

    /// Finished rows pile up otherwise — the window is small and the last few
    /// results are the only ones anybody looks at.
    private let maxJobs = 4

    private let catalog: ArchiveTypeCatalog
    private let engineSelector: ArchiveEngineSelectorProtocol

    init(catalog: ArchiveTypeCatalog, engineSelector: ArchiveEngineSelectorProtocol) {
        self.catalog = catalog
        self.engineSelector = engineSelector
    }

    /// Compresses `files` into one archive next to them.
    ///
    /// The drop grants read access to the items but not to their folder, and
    /// writing needs that — a panel the first time only, since `FolderAccessStore`
    /// reuses a bookmark on any ancestor and Downloads is entitled. Mixed
    /// selections land next to the first item, and the grant follows it.
    @discardableResult
    func compress(files: [URL], options: SevenZipCompressionOptions) -> DropJob? {
        guard let first = files.first else { return nil }
        let folder = first.deletingLastPathComponent()
        let name = CompressDestination.name(files: files, target: folder, ext: options.format.rawValue)

        let state = ArchiveState(catalog: catalog, engineSelector: engineSelector)
        // a save that hits a permission error retries once through this
        state.folderAccessProvider = { await FolderAccessStore.shared.ensureAccess(forFileIn: $0) }
        let job = DropJob(name: name, state: state)
        jobs.append(job)
        if jobs.count > maxJobs { jobs.removeFirst(jobs.count - maxJobs) }

        log.info("Drop compress starting", context: [
            "files": "\(files.count)",
            "format": options.format.rawValue,
            "level": "\(options.level)"
        ])

        Task {
            guard await FolderAccessStore.shared.ensureAccess(forFileIn: first) else {
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
                log.info("Drop compress finished", context: ["file": destination.lastPathComponent])
                finish(job, .done(destination))
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
