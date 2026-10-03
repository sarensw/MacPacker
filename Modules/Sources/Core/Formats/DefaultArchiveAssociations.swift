import Foundation

/// File association choices are distinct from the volumes an engine can read.
public enum DefaultArchiveAssociations {
    public struct Choice: Identifiable {
        public let id: String
        public let name: String
        public let extensions: [String]
    }

    /// Base archives and registered tarball compositions; never individual volumes.
    public static func choices(catalog: ArchiveTypeCatalog) -> [Choice] {
        let base = catalog.getAllTypes().filter {
            ["archive", "compression"].contains($0.kind)
                && !["ar", "chm", "msapp", "msi", "pkg", "rpm", "sea"].contains($0.id)
        }.map { Choice(id: $0.id, name: $0.name, extensions: extensions(for: $0)) }
        let tarballs = catalog.allCompositions().filter { ["tar.bz2", "tar.gz", "tar.xz"].contains($0.id) }
            .map { Choice(id: $0.id, name: $0.name, extensions: $0.extensions) }
        return (base + tarballs).filter { !$0.extensions.isEmpty }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static let excluded = Set(["apk", "ipa", "appx", "exe", "jar", "war", "epub", "xpi", "deb", "a", "lib"])

    public static func extensions(for format: ArchiveTypeDto) -> [String] {
        // Numbered volumes are discovered while extracting the first archive.
        // Never register each part as a separate default document type.
        return Set(format.extensions).subtracting(excluded).filter {
            $0.range(of: #"^(?:[r-z][0-9]+|[0-9]+)$"#, options: .regularExpression) == nil
        }.sorted()
    }
}
