//
//  ArchiveTypeId.swift
//  Modules
//
//  Created by Stephan Arenswald on 25.11.25.
//


public enum ArchiveTypeId: String, CaseIterable, Identifiable, Sendable {
    public var id: String { rawValue }
    
    case `7zip` = "7-Zip Archive"
    case bzip2  = "Bzip2 File"
    case cab    = "CAB Archive"
    case cpio   = "CPIO Archive"
    case gzip   = "Gzip File"
    case iso    = "ISO Image"
    case lha    = "LhA Archive"
    case lz4    = "Lz4 Archive"
    case lzx    = "Lzx Archive"
    case ntfs   = "NTFS Image"
    case rar    = "RAR Archive"
    case sea    = "Self-extracting Archive"
    case sit    = "StuffIt Archive"
    case sitx   = "StuffIt X Archive"
    case tar    = "Tar Archive"
    case vhdx   = "VHDX Image"
    case xz     = "XZ File"
    case Z      = "Unix Compress File"
    case zip    = "Zip Archive"
    case zipx   = "Zipx Archive"
}
