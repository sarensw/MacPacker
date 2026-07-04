//
//  SplitVolumeResolver.swift
//  Modules
//
//  Resolves any volume of a split set to the *first* volume the engine is pointed
//  at, using the split type's catalog `firstVolume` rule (a regex substitution on
//  the file name). Pure name computation — no filesystem access and no engine
//  code; which volume is first is a naming fact carried by the split type.
//

import Foundation

public enum SplitVolumeResolver {

    /// The first volume of the split set that `url` belongs to, per `split`.
    public static func firstVolume(for url: URL, split: SplitTypeDto) -> URL {
        let firstName = url.lastPathComponent.replacingOccurrences(
            of: split.firstVolume.pattern,
            with: split.firstVolume.replacement,
            options: [.regularExpression, .caseInsensitive]
        )
        return url.deletingLastPathComponent().appendingPathComponent(firstName)
    }
}
