//
//  CompositionType.swift
//  MacPackerCore
//
//  Created by Stephan Arenswald on 11.11.25.
//

import Foundation
import UniformTypeIdentifiers

public enum CompositionTypeId: String, CaseIterable {
    case `tar.bz2`  = "Bzip2 Tar Archive"
    case `tar.gz`   = "Gzip Tar Archive"
    case `tar.xz`   = "XZ Tar Archive"
}

public struct CompositionType: Hashable, Identifiable {
    public let id: CompositionTypeId
    let composition: [ArchiveTypeId]
    let uti: UTType
    let extensions: [String]
    let magicRule: [MagicRule]
    
    init(
        id: CompositionTypeId,
        composition: [ArchiveTypeId],
        uti: UTType,
        extensions: [String],
        magicRule: [MagicRule]
    ) {
        self.id = id
        self.composition = composition
        self.uti = uti
        self.extensions = extensions
        self.magicRule = magicRule
    }
}
