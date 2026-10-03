import Foundation

extension Array where Element == ArchiveUpdateItem {
    /// Only additions from disk are filtered. A Save or Save As never silently
    /// removes entries that the archive already contains.
    func excludingGitIgnoredFiles() throws -> [ArchiveUpdateItem] {
        let paths = compactMap { item -> (archivePath: String, url: URL)? in
            switch item {
            case .addFile(let path, let url, _, _): (path, url)
            case .addDirectory(let path, let url?, _, _): (path, url)
            default: nil
            }
        }
        guard !paths.isEmpty else { return self }
        // The first archive path component identifies what was selected. A
        // single selected folder is its own ignore root; its parent's rules
        // must not unexpectedly remove files from inside it. Multiple selected
        // items (including Compress Contents) share their containing folder.
        let selected = paths.filter { !$0.archivePath.contains("/") }.map(\.url)
        let filter = GitIgnoreFilter(paths: selected.isEmpty ? paths.map(\.url) : selected)
        return try filterItems(filter)
    }

    private func filterItems(_ filter: GitIgnoreFilter) throws -> [ArchiveUpdateItem] {
        try self.filter { item in
            switch item {
            case .addFile(_, let url, _, _):
                return try !filter.isIgnored(url, directory: false)
            case .addDirectory(_, let url?, _, _):
                return try !filter.isIgnored(url, directory: true)
            default:
                return true
            }
        }
    }
}

/// Reads only `.gitignore` files on the path from the selection's common parent
/// to each added item. Rules closer to the item take precedence. An ignored
/// directory cannot be re-included by a rule about a file inside it, as in Git.
public final class GitIgnoreFilter {
    private let root: [String]
    private var cachedRules: [String: [Rule]] = [:]

    public init(paths: [URL]) {
        let first = paths[0].standardizedFileURL
        var isDirectory: ObjCBool = false
        let singleDirectory = paths.count == 1
            && FileManager.default.fileExists(atPath: first.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
        var common = (singleDirectory
                      ? first : first.deletingLastPathComponent()).pathComponents
        for path in paths.dropFirst() {
            let parts = path.standardizedFileURL.deletingLastPathComponent().pathComponents
            common = Array(zip(common, parts).prefix { $0.0 == $0.1 }.map(\.0))
        }
        root = common
    }

    public func isIgnored(_ url: URL, directory: Bool) throws -> Bool {
        let parts = url.standardizedFileURL.pathComponents
        guard parts.starts(with: root) else { return false }
        var active: [(depth: Int, rule: Rule)] = []
        for depth in root.count..<parts.count {
            let parent = URL(fileURLWithPath: NSString.path(withComponents: Array(parts.prefix(depth))), isDirectory: true)
            for rule in try rules(in: parent) {
                active.append((depth, rule))
            }
            let candidate = Array(parts.prefix(depth + 1))
            let isDirectory = depth < parts.count - 1 || directory
            var ignored = false
            for (ruleDepth, rule) in active where rule.matches(Array(candidate.dropFirst(ruleDepth)), directory: isDirectory) {
                ignored = !rule.negated
            }
            if ignored { return true }
        }
        return false
    }

    private func rules(in folder: URL) throws -> [Rule] {
        let path = folder.path
        if let cached = cachedRules[path] { return cached }
        let file = folder.appendingPathComponent(".gitignore")
        guard FileManager.default.fileExists(atPath: file.path) else {
            cachedRules[path] = []
            return []
        }
        // Failure is surfaced before opening the destination. Silently ignoring
        // an unreadable rule file could publish files the user meant to exclude.
        let contents = try String(contentsOf: file, encoding: .utf8)
        let rules = contents.components(separatedBy: .newlines).compactMap(Rule.init)
        cachedRules[path] = rules
        return rules
    }

    private struct Rule {
        let negated: Bool
        let directoryOnly: Bool
        let pathPattern: Bool
        let regex: NSRegularExpression

        init?(_ line: String) {
            var pattern = line
            while pattern.last == " " {
                let slashes = pattern.dropLast().reversed().prefix(while: { $0 == "\\" }).count
                if slashes % 2 == 1 { break }
                pattern.removeLast()
            }
            guard !pattern.isEmpty, !pattern.hasPrefix("#") else { return nil }
            let negated = pattern.hasPrefix("!")
            if negated { pattern.removeFirst() }
            let directoryOnly = pattern.hasSuffix("/") && !pattern.hasSuffix("\\/")
            if directoryOnly { pattern.removeLast() }
            let pathPattern = pattern.hasPrefix("/") || pattern.contains("/")
            if pattern.hasPrefix("/") { pattern.removeFirst() }
            guard !pattern.isEmpty, let expression = Self.expression(for: pattern) else { return nil }
            self.negated = negated
            self.directoryOnly = directoryOnly
            self.pathPattern = pathPattern
            regex = expression
        }

        func matches(_ components: [String], directory: Bool) -> Bool {
            guard !components.isEmpty, !directoryOnly || directory else { return false }
            let value = pathPattern ? components.joined(separator: "/") : components.last!
            return regex.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)) != nil
        }

        private static func expression(for pattern: String) -> NSRegularExpression? {
            let chars = Array(pattern)
            var result = "^"
            var index = 0
            while index < chars.count {
                let char = chars[index]
                if char == "\\" {
                    index += 1
                    guard index < chars.count else { return nil }
                    result += NSRegularExpression.escapedPattern(for: String(chars[index]))
                } else if char == "*" {
                    if index + 1 < chars.count, chars[index + 1] == "*",
                       (index == 0 || chars[index - 1] == "/") {
                        if index + 2 < chars.count, chars[index + 2] == "/" {
                            result += "(?:.*/)?"
                            index += 2
                        } else if index > 0, index + 2 == chars.count {
                            result += ".*"
                            index += 1
                        } else {
                            result += "[^/]*"
                            index += 1
                        }
                    } else {
                        result += "[^/]*"
                    }
                } else if char == "?" {
                    result += "[^/]"
                } else if char == "[", let end = chars[(index + 1)...].firstIndex(of: "]") {
                    var contents = String(chars[(index + 1)..<end])
                    if contents.hasPrefix("!") { contents.replaceSubrange(contents.startIndex...contents.startIndex, with: "^") }
                    result += "[\(contents)]"
                    index = end
                } else {
                    result += NSRegularExpression.escapedPattern(for: String(char))
                }
                index += 1
            }
            return try? NSRegularExpression(pattern: result + "$")
        }
    }
}
