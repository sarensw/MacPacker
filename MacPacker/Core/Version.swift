//
//  Version.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 08.10.25.
//

struct Version: Comparable, LosslessStringConvertible, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int
    
    /// Default constructor using semantic versioning
    /// - Parameters:
    ///   - major: major version
    ///   - minor: minor version
    ///   - patch: patch version
    init(major: Int, minor: Int, patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }
    
    /// That's the default constructor as the usual input is Bundle.main.appVersion
    /// - Parameter description: version as a string, usually taken from Bundle.main.appVersion
    init?(_ description: String) {
        // Normalize input: trim, drop leading "v" (e.g. "v1.2.3")
        let raw = description.trimmingCharacters(in: .whitespacesAndNewlines)
            .drop(while: { $0 == "v" || $0 == "V" })

        // Split into at most 3 components
        let parts = raw.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)

        // Require at least major.minor
        guard parts.count >= 2, parts.count <= 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]) else {
            return nil
        }

        // Set patch (might be 0 if not given)
        let patch = parts.count == 3 ? Int(parts[2]) ?? 0 : 0

        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: Version, rhs: Version) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    var description: String {
        "\(major).\(minor).\(patch)"
    }

    var versionString: String { "v" + description }
}
