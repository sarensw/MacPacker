import Foundation

/// An explicit destination choice, independent of Smart Extraction's container rule.
public enum OneClickExtractionDestination: String, CaseIterable, Sendable {
    case sameFolder
    case archiveFolder
    case chooseFolder

    public static func saved(in defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: Keys.oneClickExtractionDestination)
            .flatMap(Self.init(rawValue:)) ?? .archiveFolder
    }

    /// `nil` means the caller must ask for a destination before extracting.
    public func directory(for archive: URL, detector: ArchiveTypeDetector) -> URL? {
        switch self {
        case .sameFolder:
            return archive.deletingLastPathComponent()
        case .archiveFolder:
            // Keep an existing extraction (or an extensionless source archive)
            // intact by creating a new sibling, as Smart Extraction does.
            let parent = archive.deletingLastPathComponent()
            let stripped = detector.getNameWithoutExtension(for: archive)
            let name = stripped.isEmpty || stripped == "." || stripped == ".."
                ? archive.lastPathComponent : stripped
            return Sandbox.accessSync(url: parent) {
                var folder = parent.appendingPathComponent(name, isDirectory: true)
                var suffix = 2
                while FileManager.default.fileExists(atPath: folder.path) {
                    folder = parent.appendingPathComponent("\(name) (\(suffix))", isDirectory: true)
                    suffix += 1
                }
                return folder
            }
        case .chooseFolder:
            return nil
        }
    }
}
