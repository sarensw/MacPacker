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

final class ArchiveTypeCatalog {
    static let shared = ArchiveTypeCatalog()
    
    /// This is the full list of all known archive types. Whether they are supported or
    /// not depends on which ID is registered in an archive handler. This list will allow
    /// later use cases like "I know the format, but don't support it yet"
    public private(set) var typesByID: [String: ArchiveType] = [:]
    
    private init() {
        loadAllTypes()
    }
    
    private func loadAllTypes() {
        register(
            .init(
                id: "7zip",
                kind: .archive,
                displayName: "7-Zip Archive",
                uti: UTType(importedAs: "org.7-zip.7-zip-archive"),
                extensions: ["7z"],
                magicSignatures: [
                    .init(bytes: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])
                ])
        )
        
        register(
            .init(
                id: "bzip2",
                kind: .compression,
                displayName: "Bzip2 File",
                uti: .bz2,
                extensions: ["bz2", "bzip2", "bz"],
                magicSignatures: [
                    .init(bytes: [0x42, 0x5A, 0x68])
                ])
        )
        
        register(
            .init(
                id: "cab",
                kind: .archive,
                displayName: "CAB Archive",
                uti: UTType(importedAs: "com.microsoft.cab"),
                extensions: ["cab"],
                magicSignatures: [
                    .init(bytes: [0x4D, 0x53, 0x43, 0x46])
                ])
        )
        
        register(
            .init(
                id: "cpio",
                kind: .archive,
                displayName: "CPIO Archive",
                uti: UTType(importedAs: "public.cpio-archive"),
                extensions: ["cpio"],
                magicSignatures: [
                    // cpio "new" ASCII archive file
                    .init(bytes: [0x30, 0x37, 0x30, 0x37, 0x30, 0x31]),
                    // cpio ASCII archive file with crc
                    .init(bytes: [0x30, 0x37, 0x30, 0x37, 0x30, 0x32]),
                    // cpio ASCII archive file
                    .init(bytes: [0x30, 0x37, 0x30, 0x37, 0x30, 0x37])
                ])
        )
        
        register(
            .init(
                id: "gzip",
                kind: .compression,
                displayName: "Gzip File",
                uti: .gzip,
                extensions: ["gz", "gzip"],
                magicSignatures: [
                    .init(bytes: [0x1F, 0x8B])
                ])
        )
        
        register(
            .init(
                id: "iso",
                kind: .image,
                displayName: "ISO Disk Image",
                uti: UTType(importedAs: "public.iso-image"),
                extensions: ["iso"],
                magicSignatures: [
                    .init(offset: 0x8001, bytes: [0x43, 0x44, 0x30, 0x30, 0x31]),
                    // and
                    .init(offset: 0x8801, bytes: [0x43, 0x44, 0x30, 0x30, 0x31]),
                    // and
                    .init(offset: 0x9001, bytes: [0x43, 0x44, 0x30, 0x30, 0x31])
                ])
        )
        
        register(
            .init(
                id: "lha",
                kind: .archive,
                displayName: "LhA Archive",
                uti: UTType(importedAs: "org.7-zip.lha-archive"),
                extensions: ["lha", "lzh"],
                magicSignatures: [
                    .init(offset: 0x02, bytes: [0x2D, 0x6C, 0x68, 0x30, 0x2D]),
                    // or
                    .init(offset: 0x02, bytes: [0x2D, 0x6C, 0x68, 0x35, 0x2D]),
                    // or
                    .init(offset: 0x9001, bytes: [0x2D, 0x6C, 0x68, 0x64, 0x2D])
                ])
        )
        
        register(
            .init(
                id: "lz4",
                kind: .compression,
                displayName: "Lz4 File",
                uti: UTType(importedAs: "public.lz4-archive"),
                extensions: ["lz4"],
                magicSignatures: [
                    .init(bytes: [0x04, 0x22, 0x4D, 0x18])
                ])
        )
        
        register(
            .init(
                id: "lzx",
                kind: .archive,
                displayName: "Amiga LZX Archive",
                uti: UTType(importedAs: "cx.c3.lzx-archive"),
                extensions: ["lzx"],
                magicSignatures: [])
        )
        
        register(
            .init(
                id: "rar",
                kind: .archive,
                displayName: "RAR Archive",
                uti: UTType(importedAs: "com.rarlab.rar-archive"),
                extensions: ["lzx"],
                magicSignatures: [
                    .init(bytes: [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]),
                    
                    // or
                    .init(bytes: [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00])
                ])
        )
        
        register(
            .init(
                id: "sea",
                kind: .archive,
                displayName: "Self-extracting Archive",
                uti: UTType(importedAs: "com.apple.self-extracting-archive"),
                extensions: ["sea"],
                magicSignatures: [
                    .init(bytes: [0x53, 0x74, 0x75, 0x66, 0x66, 0x49, 0x74, 0x20])
                ])
        )
        
        register(
            .init(
                id: "sit",
                kind: .archive,
                displayName: "StuffIt Archive",
                uti: UTType(importedAs: "com.stuffit.archive.sit"),
                extensions: ["sit"],
                magicSignatures: [
                    .init(bytes: [0x53, 0x74, 0x75, 0x66, 0x66, 0x49, 0x74, 0x20])
                ])
        )
        
        register(
            .init(
                id: "sitx",
                kind: .archive,
                displayName: "StuffIt X Archive",
                uti: UTType(importedAs: "com.stuffit.archive.sitx"),
                extensions: ["sitx"],
                magicSignatures: [
                    .init(bytes: [0x53, 0x74, 0x75, 0x66, 0x66, 0x49, 0x74, 0x21])
                ])
        )
        
        register(
            .init(
                id: "tar",
                kind: .archive,
                displayName: "Tar Archive",
                uti: UTType(importedAs: "public.tar-archive"),
                extensions: ["tar"],
                magicSignatures: [
                    .init(offset: 257, bytes: [0x75, 0x73, 0x74, 0x61, 0x72, 0x00, 0x30, 0x30]),
                    // or
                    .init(offset: 257, bytes: [0x75, 0x73, 0x74, 0x61, 0x72, 0x20, 0x20, 0x00])
                ])
        )
        
        register(
            .init(
                id: "tar.bz2",
                kind: .archive,
                displayName: "Bzip2 Tar Archive",
                uti: UTType(importedAs: "org.bzip.bzip2-tar-archive"),
                extensions: ["tbz2", "tbz"],
                magicSignatures: [
                    .init(bytes: [0x42, 0x5A, 0x68])
                ],
                composition: .compressed(outer: "bzip2", inner: "tar"))
        )
        
        register(
            .init(
                id: "tar.gz",
                kind: .archive,
                displayName: "Gzip Tar Archive",
                uti: UTType(importedAs: "org.gnu.gnu-zip-tar-archive"),
                extensions: ["tgz"],
                magicSignatures: [
                    .init(bytes: [0x1F, 0x8B])
                ],
                composition: .compressed(outer: "gzip", inner: "tar"))
        )
        
        register(
            .init(
                id: "tar.xz",
                kind: .archive,
                displayName: "XZ Tar Archive",
                uti: UTType(importedAs: "org.tukaani.tar-xz-archive"),
                extensions: ["txz"],
                magicSignatures: [
                    .init(bytes: [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00])
                ],
                composition: .compressed(outer: "xz", inner: "tar"))
        )
        
        register(
            .init(
                id: "xz",
                kind: .compression,
                displayName: "XZ File",
                uti: UTType(importedAs: "org.tukaani.xz-archive"),
                extensions: ["xz"],
                magicSignatures: [
                    .init(bytes: [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00])
                ])
        )
        
        register(
            .init(
                id: "Z",
                kind: .archive,
                displayName: "Unix Compress File",
                uti: UTType(importedAs: "public.z-archive"),
                extensions: ["z"],
                magicSignatures: [
                    .init(bytes: [0x1F, 0x9D])
                ])
        )
        
        register(
            .init(
                id: "zip",
                kind: .archive,
                displayName: "Zip Archive",
                uti: .zip,
                extensions: ["zip"],
                magicSignatures: [
                    .init(bytes: [0x50, 0x4B, 0x03, 0x04]),
                    // or (for empty archive)
                    .init(bytes: [0x50, 0x4B, 0x05, 0x06]),
                    // or (spanned archive)
                    .init(bytes: [0x50, 0x4B, 0x07, 0x08])
                ])
        )
    }
    
    private func register(_ type: ArchiveType) {
        typesByID[type.id] = type
    }
    
    public func allTypes() -> [ArchiveType] {
        return Array(typesByID.values)
    }
}
