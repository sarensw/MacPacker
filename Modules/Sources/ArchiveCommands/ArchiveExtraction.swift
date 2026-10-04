import Darwin
import Foundation
import Swift7zip

/// Runs a CLI extraction into a new directory, removing partial results on failure.
public enum ArchiveExtraction {
    public static func extract(_ source: URL, to destination: URL, password: String?) throws {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: destination.path) else {
            throw CommandError("The extraction destination already exists.")
        }
        let archive = try SevenZipArchive(url: VolumePath.first(source), password: password)
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        // FileManager.createDirectory succeeds for an existing directory. An
        // exclusive mkdir ensures that a racing caller's files are never removed.
        guard mkdir(destination.path, 0o700) == 0 else {
            if errno == EEXIST { throw CommandError("The extraction destination already exists.") }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        do {
            try archive.extractAll(to: destination)
        } catch {
            let extractionError = error
            do { try manager.removeItem(at: destination) }
            catch {
                throw CommandError("Extraction failed: \(extractionError.localizedDescription). Could not remove partial output at \(destination.path): \(error.localizedDescription)")
            }
            throw extractionError
        }
    }
}
