//
//  ArchiveFiles.swift
//  Modules
//
//  The files on disk an archive is made of: the file itself or, for an archive
//  split into volumes, every volume of it. What "Move archive to Trash after
//  extraction" moves — leaving a volume behind would leave the user a file
//  that is good for nothing.
//
//  Purely by name, like the rest of the split handling: the catalog's split
//  types, plus RAR's two ways of naming volumes, which 7-Zip follows on its
//  own and the catalog does not list.
//

import Foundation

public enum ArchiveFiles {

    /// RAR's volumes: `name.part1.rar`, `name.part2.rar`, … and the older
    /// `name.rar`, `name.r00`, `name.r01`, …. The labels follow the catalog's
    /// rule: every volume of a set gets the same key, and the older scheme's
    /// key is its bare `.rar`, as the spanned zip's is its bare `.zip`.
    private static let rarSplits: [(pattern: String, label: String)] = [
        (#"\.part[0-9]+\.rar$"#, ".part*.rar"),
        (#"\.r[0-9]{2,}$"#, ".rar"),
    ]

    /// The files `archive` is made of, found among `siblings` (the contents of
    /// its folder).
    ///
    /// Two files belong to the same set when they have the same key: the name
    /// with its volume suffix replaced by the split type's label, so that
    /// `x.z01`, `x.z02` and the bare `x.zip` all read `x.zip`, and `x.zip.001`
    /// reads `x.zip.001` — not `x.zip`, which is another archive. A file whose
    /// name is no volume's is only ever part of a set whose other files are.
    public static func files(of archive: URL, among siblings: [URL], splits: [SplitTypeDto]) -> [URL] {
        let rules = splits.map { (pattern: $0.pattern, label: $0.label) } + rarSplits
        let archiveKey = key(of: archive, rules: rules)
        let archiveIsVolume = isVolume(archive, rules: rules)
        let others = siblings.filter { sibling in
            sibling.lastPathComponent != archive.lastPathComponent
                && key(of: sibling, rules: rules) == archiveKey
                && (archiveIsVolume || isVolume(sibling, rules: rules))
        }
        return [archive] + others.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func isVolume(_ file: URL, rules: [(pattern: String, label: String)]) -> Bool {
        rules.contains { matches(file.lastPathComponent, $0.pattern) }
    }

    private static func key(of file: URL, rules: [(pattern: String, label: String)]) -> String {
        let name = file.lastPathComponent
        guard let rule = rules.first(where: { matches(name, $0.pattern) }) else {
            return name.lowercased()
        }
        return name.replacingOccurrences(
            of: rule.pattern, with: rule.label,
            options: [.regularExpression, .caseInsensitive]
        ).lowercased()
    }

    private static func matches(_ name: String, _ pattern: String) -> Bool {
        name.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
