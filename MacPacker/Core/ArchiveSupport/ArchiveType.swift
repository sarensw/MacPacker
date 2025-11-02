//
//  ArchiveType.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 01.11.25.
//

import Foundation
import UniformTypeIdentifiers

struct ArchiveType: Hashable, Identifiable {
    let id: String
    let kind: Kind
    let displayName: String
    let uti: UTType
    let extensions: [String]
    let magicSignatures: [MagicSignature]
    let composition: Composition?
    let multipartPatterns: [MultipartPattern]
    
    init(
        id: String,
        kind: Kind,
        displayName: String,
        uti: UTType,
        extensions: [String],
        magicSignatures: [MagicSignature] = [],
        composition: Composition? = nil,
        multipartPatterns: [MultipartPattern] = []
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.uti = uti
        self.extensions = extensions
        self.magicSignatures = magicSignatures
        self.composition = composition
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
    
    enum Composition: Hashable {
        case compressed(outer: String, inner: String)
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
