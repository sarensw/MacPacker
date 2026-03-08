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

final public class ArchiveTypeDetector: Sendable {
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
    
    func getFileSize(for url: URL) -> UInt64? {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
            return UInt64(resourceValues.fileSize ?? 0)
        } catch {
            print("Error getting file size: \(error.localizedDescription)")
            return nil
        }
    }

    func detectByMagicNumber(for url: URL) -> DetectionResult? {
        // get a file handle to read the first bytes
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { handle.closeFile() }
        
        // read the first 65.536 bytes (we're reading that much
        // because iso files are detected at 0x8000, 0x8080 and 0x9000)
        let headerData = try? handle.read(upToCount: 65536)
        guard let header = headerData, !header.isEmpty else { return nil }
        let headerBytes = [UInt8](header)

        // read the last 512 bytes (big enough to get the magic for a dmg)
        guard let fileSize = getFileSize(for: url) else { return nil }
        let trailerSize = min(fileSize, 512)
        let trailerOffset = fileSize - trailerSize
        do { try handle.seek(toOffset: trailerOffset) } catch { return nil }
        let trailerData = try? handle.read(upToCount: Int(trailerSize))
        guard let trailer = trailerData, !trailer.isEmpty else { return nil }
        let trailerBytes = [UInt8](trailer)
        
        // now scan all types and see if any rule matches
        for type in catalog.getAllTypes() {
            for rule in type.rules {
                switch rule.policy {
                case .any:
                    for signature in rule.tests {
                        if signature.type == "end_signature" {
                            let start = trailerBytes.count - signature.offset
                            let end = start + signature.bytes.count

                            if start >= 0 {
                                let slice = Array(trailerBytes[start..<end])
                                if slice == signature.bytes {
                                    return DetectionResult(
                                        type: type,
                                        composition: nil,
                                        source: .magic
                                    )
                                }
                            }
                        } else {
                            let start = signature.offset
                            let end = start + signature.bytes.count

                            if end <= headerBytes.count {
                                // check if the given slice matches the known signature
                                let slice = Array(headerBytes[start..<end])
                                if slice == signature.bytes {
                                    return DetectionResult(
                                        type: type,
                                        composition: nil,
                                        source: .magic
                                    )
                                }
                            }
                        }
                    }
                case .all:
                    var result = true
                    for signature in rule.tests {
                        if signature.type == "end_signature" {
                            let start = trailerBytes.count - signature.offset
                            let end = start + signature.bytes.count

                            if start >= 0 {
                                let slice = Array(trailerBytes[start..<end])
                                if slice == signature.bytes {
                                    result = result && true
                                } else {
                                    result = false
                                }
                            } else {
                                result = false
                            }
                        } else {
                            let start = signature.offset
                            let end = start + signature.bytes.count

                            if end <= headerBytes.count {
                                let slice = Array(headerBytes[start..<end])
                                if slice == signature.bytes {
                                    result = result && true
                                } else {
                                    result = false
                                }
                            } else {
                                result = false
                            }
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
