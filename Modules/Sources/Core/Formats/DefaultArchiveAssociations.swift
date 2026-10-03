import Foundation

/// File association choices are distinct from the volumes an engine can read.
public enum DefaultArchiveAssociations {
    private static let excluded = Set(["apk", "ipa", "appx", "exe", "jar", "war", "epub", "xpi", "deb", "a", "lib"])

    public static func extensions(for format: ArchiveTypeDto) -> [String] {
        // Numbered volumes are discovered while extracting the first archive.
        // Never register each part as a separate default document type.
        return Set(format.extensions).subtracting(excluded).filter {
            $0.range(of: #"^(?:[r-z][0-9]+|[0-9]+)$"#, options: .regularExpression) == nil
        }.sorted()
    }
}
