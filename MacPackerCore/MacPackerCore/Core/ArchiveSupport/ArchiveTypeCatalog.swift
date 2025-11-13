//
//  ArchiveTypeCatalog.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 01.11.25.
//
// References:
// - https://en.wikipedia.org/wiki/List_of_file_signatures
// - https://gist.github.com/rmorey/b8d1b848086bdce026a9f57732a3b858

import UniformTypeIdentifiers

private extension String {
    func hexBytes() -> [UInt8]? {
        // keep only hex digits, drop whitespace
        let filtered = self.filter { $0.isHexDigit }
        guard filtered.count % 2 == 0 else { return nil }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(filtered.count / 2)

        var i = filtered.startIndex
        while i < filtered.endIndex {
            let j = filtered.index(i, offsetBy: 2)
            guard let b = UInt8(filtered[i..<j], radix: 16) else { return nil }
            bytes.append(b)
            i = j
        }
        return bytes
    }
}

extension ArchiveType.MagicSignature {
    static func hex(_ s: String, offset: Int = 0) -> Self {
        .init(offset: offset, bytes: s.hexBytes() ?? [])
    }
    
    static func any(_ sigs: ArchiveType.MagicSignature...) -> Self {
        .init(offset: 0, bytes: sigs.flatMap(\.bytes))
    }
    
    static func all(_ sigs: ArchiveType.MagicSignature...) -> Self {
        .init(offset: 0, bytes: sigs.flatMap(\.bytes))
    }
}

struct MagicRule: Hashable {
    enum Policy { case any, all }
    let policy: Policy
    let signatures: [ArchiveType.MagicSignature]
    
    static func any(_ sigs: ArchiveType.MagicSignature...) -> MagicRule {
        .init(policy: .any, signatures: sigs)
    }
    
    static func all(_ sigs: ArchiveType.MagicSignature...) -> MagicRule {
        .init(policy: .all, signatures: sigs)
    }
}

enum Sig { case any([ArchiveType.MagicSignature]) }

public enum ArchiveTypeId: String, CaseIterable {
    case `7zip` = "7-Zip Archive"
    case bzip2  = "Bzip2 File"
    case cab    = "CAB Archive"
    case cpio   = "CPIO Archive"
    case gzip   = "Gzip File"
    case iso    = "ISO Image"
    case lha    = "LhA Archive"
    case lz4    = "Lz4 Archive"
    case lzx    = "Lzx Archive"
    case rar    = "RAR Archive"
    case sea    = "Self-extracting Archive"
    case sit    = "StuffIt Archive"
    case sitx   = "StuffIt X Archive"
    case tar    = "Tar Archive"
    case vhdx    = "VHDX Image"
    case xz     = "XZ File"
    case Z      = "Unix Compress File"
    case zip    = "Zip Archive"
    case zipx    = "Zipx Archive"
}

final class ArchiveTypeCatalog {
    static let shared = ArchiveTypeCatalog()
    
    /// This is the full list of all known archive types. Whether they are supported or
    /// not depends on which ID is registered in an archive handler. This list will allow
    /// later use cases like "I know the format, but don't support it yet"
    public private(set) var typesByID: [ArchiveTypeId: ArchiveType] = [:]
    public private(set) var compositionsByID: [CompositionTypeId: CompositionType] = [:]
    
    private init() {
        loadAllArchiveTypes()
        loadAllCompoundTypes()
        loadAllSpecialTypes()
    }
    
    private func ra(_ id: ArchiveTypeId, uti: String, ext: [String], rls: [MagicRule]) {
        register(id, type: .archive, uti: UTType.init(importedAs: uti), ext: ext, rls: rls)
    }
    
    private func ra(_ id: ArchiveTypeId, uti: UTType, ext: [String], rls: [MagicRule]) {
        register(id, type: .archive, uti: uti, ext: ext, rls: rls)
    }
    
    private func rc(_ id: ArchiveTypeId, uti: String, ext: [String], rls: [MagicRule]) {
        register(id, type: .compression, uti: UTType.init(importedAs: uti), ext: ext, rls: rls)
    }
    
    private func rc(_ id: ArchiveTypeId, uti: UTType, ext: [String], rls: [MagicRule]) {
        register(id, type: .compression, uti: uti, ext: ext, rls: rls)
    }
    
    private func ri(_ id: ArchiveTypeId, uti: String, ext: [String], rls: [MagicRule]) {
        register(id, type: .image, uti: UTType.init(importedAs: uti), ext: ext, rls: rls)
    }
    
    private func ri(_ id: ArchiveTypeId, uti: UTType, ext: [String], rls: [MagicRule]) {
        register(id, type: .image, uti: uti, ext: ext, rls: rls)
    }
    
    private func rco(_ id: CompositionTypeId, composition: [ArchiveTypeId], uti: String, ext: [String], rls: [MagicRule]) {
        registerComposition(id, composition: composition, uti: UTType.init(importedAs: uti), ext: ext, rls: rls)
    }
    
    private func rco(_ id: CompositionTypeId, composition: [ArchiveTypeId], uti: UTType, ext: [String], rls: [MagicRule]) {
        registerComposition(id, composition: composition, uti: uti, ext: ext, rls: rls)
    }
    
    private func register(_ id: ArchiveTypeId, type: ArchiveType.Kind, uti: UTType, ext: [String], rls: [MagicRule]) {
        let archiveType = ArchiveType(
            id: id,
            kind: type,
            displayName: id.rawValue,
            uti: uti,
            extensions: ext,
            magicRule: rls
        )
        typesByID[id] = archiveType
    }
    
    private func registerComposition(_ id: CompositionTypeId, composition: [ArchiveTypeId], uti: UTType, ext: [String], rls: [MagicRule]) {
        let compositionType = CompositionType(
            id: id,
            composition: composition,
            uti: uti,
            extensions: ext,
            magicRule: rls
        )
        compositionsByID[id] = compositionType
    }
    
    private func loadAllSpecialTypes() {
        
    }
    
    private func loadAllCompoundTypes() {
        rco(.`tar.lz4`, composition: [.tar, .lz4],      uti: "public.lz4-tar-archive",      ext: ["tlz4", "tar.lz4"],    rls: [.any(.hex("04 22 4D 18"))])
        rco(.`tar.bz2`, composition: [.tar, .bzip2],    uti: "org.bzip.bzip2-tar-archive",  ext: ["tbz2", "tbz", "tbzip2", "tb", "tar.bz2"],    rls: [.any(.hex("42 5A 68"))])
        rco(.`tar.gz`,  composition: [.tar, .gzip],     uti: "org.gnu.gnu-zip-tar-archive", ext: ["tgz", "tgzip", "tar.gz"],             rls: [.any(.hex("1F 8B"))])
        rco(.`tar.xz`,  composition: [.tar, .xz],       uti: "org.tukaani.tar-xz-archive",  ext: ["txz", "tar.xz"],             rls: [.any(.hex("FD 37 7A 58 5A 00"))])
    }
    
    private func loadAllArchiveTypes() {
        // compressions
        rc(.bzip2,      uti: .bz2,                          ext: ["bz2", "bzip2", "tb"],    rls: [.any(.hex("42 5A 68"))])
        rc(.gzip,       uti: .gzip,                         ext: ["gz", "gzip"],            rls: [.any(.hex("1F 8B"))])
        rc(.lz4,        uti: "public.lz4-archive",          ext: ["lz4"],                   rls: [.any(.hex("04 22 4D 18"))])
        rc(.xz,         uti: "org.tukaani.xz-archive",      ext: ["xz"],                    rls: [.any(.hex("FD 37 7A 58 5A 00"))])
        
        // archives
        ra(.`7zip`,     uti: "org.7-zip.7-zip-archive",     ext: ["7z"],                    rls: [.any(.hex("37 7A BC AF 27 1C"))])
        ra(.cab,        uti: "com.microsoft.cab",           ext: ["cab"],                   rls: [.any(.hex("4D 53 43 46"))])
        ra(.cpio,       uti: "public.cpio-archive",         ext: ["cpio"],                  rls: [.any(
            .hex("30 37 30 37 30 31"),
            .hex("30 37 30 37 30 32"),
            .hex("30 37 30 37 30 37")
        )])
        ra(.lha,        uti: "org.7-zip.lha-archive",       ext: ["lha", "lzh"],            rls: [.any(
            .hex("2D 6C 68 30 2D", offset: 0x02),
            .hex("2D 6C 68 35 2D", offset: 0x02),
            .hex("2D 6C 68 64 2D", offset: 0x02)
        )])
        ra(.lzx,        uti: "cx.c3.lzx-archive",           ext: ["lzx"],                   rls: [])
        ra(.rar,        uti: "com.rarlab.rar-archive",      ext: ["rar"],                   rls: [.any(
            .hex("52 61 72 21 1A 07 00"),
            .hex("52 61 72 21 1A 07 01 00")
        )])
        ra(.sea,        uti: "com.apple.self-extracting-archive", ext: ["sea"],             rls: [.any(.hex("53 74 75 66 66 49 74 20"))])
        ra(.sit,        uti: "com.stuffit.archive.sit",     ext: ["sit"],                   rls: [.any(.hex("53 74 75 66 66 49 74 20"))])
        ra(.sitx,       uti: "com.stuffit.archive.sitx",    ext: ["sitx"],                  rls: [.any(.hex("53 74 75 66 66 49 74 21"))])
        ra(.tar,        uti: "public.tar-archive",          ext: ["tar"],                   rls: [.any(
            .hex("75 73 74 61 72 00 30 30", offset: 257),
            .hex("75 73 74 61 72 20 20 00", offset: 257)
        )])
        ra(.Z,          uti: "public.z-archive",            ext: ["z"],                     rls: [.any(.hex("1F 9D"))])
        ra(.zip,        uti: .zip,                          ext: ["zip"],                   rls: [.any(
            .hex("50 4B 03 04"),
            .hex("50 4B 03 06"), // (for empty archive)
            .hex("50 4B 03 08")  // (spanned archive)
        )])
        ra(.zipx,        uti: "com.winzip.zipx-archive",    ext: ["zipx"],                   rls: [.any(
            .hex("50 4B 03 04"),
            .hex("50 4B 03 06"), // (for empty archive)
            .hex("50 4B 03 08")  // (spanned archive)
        )])
        
        // images
        ri(.iso,        uti: "public.iso-image",            ext: ["iso"],                   rls: [.all(
            .hex("43 44 30 30 31", offset: 0x8001),
            .hex("43 44 30 30 31", offset: 0x8801),
            .hex("43 44 30 30 31", offset: 0x9001)
        )])
        ri(.vhdx,       uti: .diskImage,            ext: ["vhdx"],                   rls: [.any(
            .hex("76 68 64 78 66 69 6C 65")
        )])
    }
    
    public func allTypes() -> [ArchiveType] {
        return Array(typesByID.values)
    }
    
    public func allCompositions() -> [CompositionType] {
        return Array(compositionsByID.values)
    }
}
