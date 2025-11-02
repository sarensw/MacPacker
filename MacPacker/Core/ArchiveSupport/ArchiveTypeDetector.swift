//
//  ArchiveTypeIdentifier.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 01.11.25.
//

import Foundation
import UniformTypeIdentifiers

enum DetectionSource: String {
    case fileExtension
    case systemUTI
    case magic
    case combined
}

struct DetectionResult {
    let type: ArchiveType
    let confidence: Double
    let source: DetectionSource
    let notes: String?
}

class ArchiveTypeDetector {
    func detect(for url: URL) -> DetectionResult? {
        if let byExt = detectByExtension(for: url) {
            return byExt
        }
        
        if let byMagic = detectByMagicNumber(for: url) {
            return byMagic
        }
        
        return nil
    }
    
    func detectBy(ext: String) -> DetectionResult? {
        let catalog = ArchiveTypeCatalog.shared
        
        if let type = catalog.allTypes().first(where: { $0.extensions.contains(ext) }) {
            return DetectionResult(
                type: type,
                confidence: 0.6,
                source: .fileExtension,
                notes: nil
            )
        }
        
        return nil
    }
    
    func detectByExtension(for url: URL) -> DetectionResult? {
        let catalog = ArchiveTypeCatalog.shared
        let lc = url.pathExtension.lowercased()
        
        if let type = catalog.allTypes().first(where: { $0.extensions.contains(lc) }) {
            return DetectionResult(
                type: type,
                confidence: 0.6,
                source: .fileExtension,
                notes: nil
            )
        }
        
        return nil
    }
    
    func detectByMagicNumber(for url: URL) -> DetectionResult? {
        let catalog = ArchiveTypeCatalog.shared
        
        // get a file handle to read the first bytes
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { handle.closeFile() }
        
        // read the first 65.536 bytes (we're reading that much
        // because iso files are detected at 0x8000, 0x8080 and 0x9000)
        let data = try? handle.read(upToCount: 65536)
        guard let header = data, !header.isEmpty else { return nil }
        let bytes = [UInt8](header)
        
        // now scann all types and see if there is any signature mapping
        for type in catalog.allTypes() {
            for signature in type.magicSignatures {
                let start = signature.offset
                let end = start + signature.bytes.count
                
                if end <= bytes.count {
                    // check if the given slice matches the known signature
                    let slice = Array(bytes[start..<end])
                    if slice == signature.bytes {
                        return DetectionResult(
                            type: type,
                            confidence: 1.0,
                            source: .magic,
                            notes: nil
                        )
                    }
                }
            }
        }
        
        return nil
    }
}
