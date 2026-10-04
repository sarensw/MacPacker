import Foundation

/// Checks incoming links against the tree that merge/replace will actually install.
/// It expands links component by component, before interpreting any later "..".
enum ExtractionLinkSafety {
    static func validate(staged: URL, output: URL, merge: Bool, discardExisting: Bool) throws {
        let fm = FileManager.default
        func kind(_ url: URL?) -> FileAttributeType? {
            guard let url else { return nil }
            return (try? fm.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType
        }
        // Return the winning physical entry, without following any parent links.
        func entry(_ parts: [String]) -> (url: URL, incoming: Bool)? {
            var incoming: URL? = staged
            var existing: URL? = discardExisting ? nil : output
            var winner: (url: URL, incoming: Bool)?
            for (index, part) in parts.enumerated() {
                incoming = incoming?.appendingPathComponent(part)
                existing = existing?.appendingPathComponent(part)
                let a = kind(incoming), b = kind(existing)
                if a == nil { incoming = nil }
                if b == nil { existing = nil }
                if merge, let old = existing {
                    winner = (old, false)
                    if b != .typeDirectory || a != .typeDirectory { incoming = nil }
                } else if let new = incoming {
                    winner = (new, true)
                    existing = nil
                } else if let old = existing { winner = (old, false) }
                else { return nil }
                if kind(winner?.url) != .typeDirectory && index < parts.count - 1 { return nil }
            }
            return winner
        }
        func safe(_ path: [String]) -> Bool {
            var pending = path[...]
            var resolved: [String] = []
            var expansions = 0
            while let part = pending.first {
                pending = pending.dropFirst()
                if part.isEmpty || part == "." { continue }
                if part == ".." {
                    guard !resolved.isEmpty else { return false }
                    resolved.removeLast()
                    continue
                }
                let next = resolved + [part]
                if let node = entry(next), kind(node.url) == .typeSymbolicLink {
                    expansions += 1
                    guard expansions <= 40,
                          let target = try? fm.destinationOfSymbolicLink(atPath: node.url.path),
                          !target.hasPrefix("/"), !target.isEmpty else { return false }
                    pending = (target.split(separator: "/").map(String.init) + pending)[...]
                } else { resolved.append(part) }
            }
            return true
        }
        func visit(_ folder: URL, parts: [String]) throws {
            for child in try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                try Task.checkCancellation()
                let relative = parts + [child.lastPathComponent]
                if kind(child) == .typeDirectory { try visit(child, parts: relative) }
                else if kind(child) == .typeSymbolicLink,
                        entry(relative)?.incoming == true, !safe(relative) {
                    throw ArchiveError.extractionFailed("A symbolic link would escape the extraction folder or form a cycle: " + relative.joined(separator: "/"))
                }
            }
        }
        try visit(staged, parts: [])
    }
}
