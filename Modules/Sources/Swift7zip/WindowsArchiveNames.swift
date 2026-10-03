import Foundation

/// Conservative filename checks for ordinary Windows extraction tools. This is
/// not a promise about archive codecs, symbolic links or the chosen destination's
/// total path length. Nothing here renames an entry.
/// https://learn.microsoft.com/windows/win32/fileio/naming-a-file
enum WindowsArchiveNames {
    /// All invalid or colliding entry paths, in a stable order for the error UI.
    /// Implied directories participate too: `Docs/a` and `docs/b` must not merge.
    static func conflicts(in entries: [(path: String, isDirectory: Bool)]) -> [String] {
        struct Node {
            let spelling: String
            let entry: String
            let isDirectory: Bool
        }
        var nodes: [String: Node] = [:]
        var problems: Set<String> = []
        let reserved = Set(["CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$"]
            + ["COM", "LPT"].flatMap { prefix in
                ["1", "2", "3", "4", "5", "6", "7", "8", "9", "¹", "²", "³"].map { prefix + $0 }
            })
        for entry in entries {
            var path = entry.path
            if entry.isDirectory && path.hasSuffix("/") { path.removeLast() }
            let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            var prefixes: [String] = []
            for (index, part) in parts.enumerated() {
                let base = part.split(separator: ".", omittingEmptySubsequences: false).first.map(String.init) ?? ""
                if part.isEmpty || part == "." || part == ".." || part.hasSuffix(".") || part.hasSuffix(" ")
                    || part.utf16.count > 255 || reserved.contains(base.uppercased())
                    || part.unicodeScalars.contains(where: { $0.value < 32 || "<>:\"\\|?*".unicodeScalars.contains($0) }) {
                    problems.insert(entry.path)
                }
                prefixes.append(part)
                let spelling = prefixes.joined(separator: "/")
                let key = spelling.precomposedStringWithCanonicalMapping.uppercased()
                let directory = index < parts.count - 1 || entry.isDirectory
                if let old = nodes[key] {
                    if old.spelling != spelling || old.isDirectory != directory || !directory {
                        problems.formUnion([old.entry, entry.path])
                    }
                } else {
                    nodes[key] = Node(spelling: spelling, entry: entry.path, isDirectory: directory)
                }
            }
        }
        return problems.sorted()
    }
}
