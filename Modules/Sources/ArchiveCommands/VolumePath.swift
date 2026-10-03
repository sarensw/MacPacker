import Foundation

public enum VolumePath {
    /// Only rewrites the name; the engine reads each part on demand.
    public static func first(_ url: URL) -> URL {
        let name = url.lastPathComponent
        if name.range(of: #"\.(7z|zip|tar)\.[0-9]{3,}$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return url.deletingLastPathComponent().appendingPathComponent(
                name.replacingOccurrences(of: #"\.[0-9]{3,}$"#, with: ".001", options: .regularExpression))
        }
        if name.range(of: #"\.r[0-9]{2}$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return url.deletingLastPathComponent().appendingPathComponent(String(name.dropLast(3)) + "rar")
        }
        if let range = name.range(of: #"(?<=\.part)[0-9]+(?=\.rar$)"#, options: [.regularExpression, .caseInsensitive]) {
            let first = String(repeating: "0", count: name[range].count - 1) + "1"
            return url.deletingLastPathComponent().appendingPathComponent(name.replacingCharacters(in: range, with: first))
        }
        return url
    }
}
