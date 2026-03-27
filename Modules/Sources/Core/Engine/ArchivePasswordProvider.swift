//
//  ArchivePasswordRequesst.swift
//  Modules
//
//  Created by Stephan Arenswald on 25.03.26.
//

import Foundation

public struct ArchivePasswordRequest: Sendable {
    public let url: URL
    public let attempt: Int
    public let message: String?
    
    public init(url: URL, attempt: Int = 1, message: String? = nil) {
        self.url = url
        self.attempt = attempt
        self.message = message
    }
}

public typealias ArchivePasswordResolver = @Sendable (ArchivePasswordRequest) async -> String?

public typealias ArchivePasswordUserProvider = @Sendable (ArchivePasswordRequest) async -> String?
