//
//  ArchiveTypeIdentifier.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 01.11.25.
//

import Foundation
import UniformTypeIdentifiers

public enum DetectionSource: String {
    case fileExtension
    case systemUTI
    case magic
    case combined
}

public struct DetectionResult: CustomStringConvertible {
    public let type: ArchiveTypeDto
    public let composition: CompositionTypeDto?
    public let source: DetectionSource
    
    public var description: String {
        if let composition {
            return "\(type) (\(composition))"
        } else {
            return "\(type)"
        }
    }
}

public class ArchiveTypeDetector {
    private let catalog: ArchiveTypeCatalog
    
    public init(catalog: ArchiveTypeCatalog) {
        self.catalog = catalog
    }
    
    public func getNameWithoutExtension(for url: URL) -> String {
        var name = url.lastPathComponent
        if let byExt = detectByExtension(for: url, considerComposition: true) {
            if let composition = byExt.composition {
                for compExt in composition.extensions {
                    if name.hasSuffix(".\(compExt)") {
                        name.removeLast(compExt.count + 1)
                        break
                    }
                }
            } else {
                for ext in byExt.type.extensions {
                    if name.hasSuffix(".\(ext)") {
                        name.removeLast(ext.count + 1)
                        break
                    }
                }
            }
        }
        
        return url.lastPathComponent
    }
    
    public func detect(for url: URL, considerComposition: Bool = true) -> DetectionResult? {
        if let byExt = detectByExtension(for: url, considerComposition: considerComposition) {
            return byExt
        }
        
        if let byMagic = detectByMagicNumber(for: url) {
            return byMagic
        }
        
        return nil
    }
    
    func detectBy(ext: String, considerComposition: Bool = true) -> DetectionResult? {
        let dummyUrl = URL(fileURLWithPath: "fakePath.\(ext)")
        let result = detectByExtension(for: dummyUrl, considerComposition: considerComposition)
        return result
    }
    
    func detectByExtension(for url: URL, considerComposition: Bool) -> DetectionResult? {
        let lc = url.pathExtension.lowercased()
        
        // first check if this is a known composition (e.g. tar.gz)
        if considerComposition {
            for composition in catalog.allCompositions() {
                for ext in composition.extensions {
                    if url.lastPathComponent.lowercased().hasSuffix(".\(ext.lowercased())") {
                        // composition found
                        if let baseType = catalog.getType(for: composition.components.first!) {
                            
                            return DetectionResult(
                                type: baseType,
                                composition: composition,
                                source: .fileExtension
                            )
                        } else {
                            Logger.error("Composition found, but could not retrieve the base type for \(ext)")
                        }
                    }
                }
            }
        }
        
        if let type = catalog.getType(where: { $0.extensions.contains(lc) }) {
            return DetectionResult(
                type: type,
                composition: nil,
                source: .fileExtension
            )
        }
        
        return nil
    }
    
    func detectByMagicNumber(for url: URL) -> DetectionResult? {
        // get a file handle to read the first bytes
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { handle.closeFile() }
        
        // read the first 65.536 bytes (we're reading that much
        // because iso files are detected at 0x8000, 0x8080 and 0x9000)
        let data = try? handle.read(upToCount: 65536)
        guard let header = data, !header.isEmpty else { return nil }
        let bytes = [UInt8](header)
        
        // now scan all types and see if any rule matches
        for type in catalog.getAllTypes() {
            for rule in type.rules {
                switch rule.policy {
                case .any:
                    for signature in rule.tests {
                        let start = signature.offset
                        let end = start + signature.bytes.count
                        
                        if end <= bytes.count {
                            // check if the given slice matches the known signature
                            let slice = Array(bytes[start..<end])
                            if slice == signature.bytes {
                                return DetectionResult(
                                    type: type,
                                    composition: nil,
                                    source: .magic
                                )
                            }
                        }
                    }
                case .all:
                    var result = true
                    for signature in rule.tests {
                        let start = signature.offset
                        let end = start + signature.bytes.count
                        
                        if end <= bytes.count {
                            let slice = Array(bytes[start..<end])
                            if slice == signature.bytes {
                                result = result && true
                            } else {
                                result = false
                            }
                        } else {
                            result = false
                        }
                    }
                    
                    if result {
                        return DetectionResult(
                            type: type,
                            composition: nil,
                            source: .magic,
                        )
                    }
                }
            }
        }
        
        return nil
    }
}
