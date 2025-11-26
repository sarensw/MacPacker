//
//  ArchiveCapabilities.swift
//  Modules
//
//  Created by Stephan Arenswald on 25.11.25.
//




public struct ArchiveCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    static let listContents   = ArchiveCapabilities(rawValue: 1 << 0)
    static let extractFiles   = ArchiveCapabilities(rawValue: 1 << 1)
    static let create         = ArchiveCapabilities(rawValue: 1 << 2)
    static let delete         = ArchiveCapabilities(rawValue: 1 << 3)
    static let add            = ArchiveCapabilities(rawValue: 1 << 4)
    static let rewriteInPlace = ArchiveCapabilities(rawValue: 1 << 5)
}