//
//  ArchiveType.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 01.11.25.
//

import Foundation
import UniformTypeIdentifiers

public struct ArchiveType: Hashable, Identifiable, Sendable {
    public let id: ArchiveTypeId
    let kind: Kind
    let displayName: String
    let uti: UTType
    let extensions: [String]
    let magicRule: [MagicRule]
    let multipartPatterns: [MultipartPattern]
    
    init(
        id: ArchiveTypeId,
        kind: Kind,
        displayName: String,
        uti: UTType,
        extensions: [String],
        magicRule: [MagicRule],
        multipartPatterns: [MultipartPattern] = []
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.uti = uti
        self.extensions = extensions
        self.magicRule = magicRule
        self.multipartPatterns = multipartPatterns
    }
    
    struct MagicSignature: Hashable {
        let offset: Int
        let bytes: [UInt8]
        
        init(offset: Int = 0, bytes: [UInt8]) {
            self.offset = offset
            self.bytes = bytes
        }
    }
    
    enum Kind: Hashable {
        case archive
        case compression
        case image
    }
    
    struct MultipartPattern: Hashable {
        enum Kind {
            case numericSuffix, rarPartNN
        }
        let kind: Kind
        
        init(kind: Kind) {
            self.kind = kind
        }
    }
}
