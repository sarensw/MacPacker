import Foundation

public enum ExtractionConflictChoice: Sendable {
    case replaceAll, merge, cancel, newFolder
}

public struct ExtractionConflict: Sendable {
    public let destination: URL
    public let names: [String]
}

/// Installs already extracted contents; the engine never writes over user data.
enum ExtractionDestination {
    struct Result {
        let destination: URL
        let skippedExisting: Bool
        let retainedBackup: URL?
    }

    static func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    static func uniqueFolder(_ proposed: URL) -> URL {
        var result = proposed
        var index = 2
        while exists(result) {
            result = proposed.deletingLastPathComponent().appendingPathComponent("\(proposed.lastPathComponent) (\(index))")
            index += 1
        }
        return result
    }

    static func conflicts(staged: URL, target: URL, folderIsOutput: Bool) throws -> [String] {
        if folderIsOutput && exists(target) { return [target.lastPathComponent] }
        return try FileManager.default.contentsOfDirectory(at: staged, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent).filter { exists(target.appendingPathComponent($0)) }.sorted()
    }

    static func install(staged: URL, target: URL, choice: ExtractionConflictChoice, folderIsOutput: Bool = false,
                        trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws -> Result {
        if choice == .cancel { throw CancellationError() }
        let fm = FileManager.default
        let output = choice == .newFolder ? uniqueFolder(target) : target
        try ExtractionLinkSafety.validate(staged: staged, output: output, merge: choice == .merge,
                                          discardExisting: choice == .newFolder || (choice == .replaceAll && folderIsOutput))
        let backup = staged.deletingLastPathComponent().appendingPathComponent("MacPacker replaced items \(UUID().uuidString)")
        var moved: [(URL, URL)] = []
        var saved: [(URL, URL)] = []
        var created: [URL] = []
        var skipped = false
        func isDirectory(_ url: URL) -> Bool {
            (try? fm.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeDirectory
        }
        func ensureDirectory(_ url: URL) throws {
            if exists(url) {
                guard isDirectory(url) else { throw CocoaError(.fileWriteFileExists) }
            } else {
                try fm.createDirectory(at: url, withIntermediateDirectories: false)
                created.append(url)
            }
        }
        func move(_ source: URL, _ destination: URL) throws {
            try Task.checkCancellation()
            if exists(destination) {
                if choice == .merge {
                    // Never follow destination symlinks, including links to folders.
                    if isDirectory(source) && isDirectory(destination) {
                        for child in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                            try move(child, destination.appendingPathComponent(child.lastPathComponent))
                        }
                    } else { skipped = true }
                    return
                }
                try fm.createDirectory(at: backup, withIntermediateDirectories: true)
                let savedURL = backup.appendingPathComponent(UUID().uuidString + "-" + destination.lastPathComponent)
                try fm.moveItem(at: destination, to: savedURL)
                saved.append((savedURL, destination))
            }
            try fm.moveItem(at: source, to: destination)
            moved.append((destination, source))
        }
        do {
            if choice == .replaceAll && folderIsOutput && exists(output) {
                try fm.createDirectory(at: backup, withIntermediateDirectories: true)
                let savedURL = backup.appendingPathComponent(output.lastPathComponent)
                try fm.moveItem(at: output, to: savedURL)
                saved.append((savedURL, output))
            }
            try ensureDirectory(output)
            for child in try fm.contentsOfDirectory(at: staged, includingPropertiesForKeys: nil) {
                let destination = output.appendingPathComponent(child.lastPathComponent)
                guard destination.standardizedFileURL != staged.standardizedFileURL,
                      destination.standardizedFileURL != backup.standardizedFileURL else { throw CocoaError(.fileWriteInvalidFileName) }
                try move(child, destination)
            }
        } catch {
            // Restore originals on cancellation or a failed move. If restoration
            // itself fails, leave the backup intact for recovery.
            for (from, to) in moved.reversed() { try? fm.moveItem(at: from, to: to) }
            for url in created.reversed() {
                if (try? fm.contentsOfDirectory(atPath: url.path).isEmpty) == true { try? fm.removeItem(at: url) }
            }
            for (from, to) in saved.reversed() { try? fm.moveItem(at: from, to: to) }
            if (try? fm.contentsOfDirectory(atPath: backup.path).isEmpty) == true { try? fm.removeItem(at: backup) }
            throw error
        }
        var retainedBackup: URL?
        if exists(backup) {
            do { try trash(backup) }
            catch { retainedBackup = backup }
        }
        return Result(destination: output, skippedExisting: skipped, retainedBackup: retainedBackup)
    }
}
