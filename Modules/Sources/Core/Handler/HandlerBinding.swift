//
//  HandlerBinding.swift
//  Modules
//
//  Created by Stephan Arenswald on 25.11.25.
//


public struct HandlerBinding {
    public let formatId: ArchiveTypeId
    public let archiveEngineId: ArchiveEngineType
    public let capabilities: ArchiveCapabilities
    public let isDefault: Bool
}
