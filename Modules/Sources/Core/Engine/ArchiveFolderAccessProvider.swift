//
//  ArchiveFolderAccessProvider.swift
//  Modules
//
//  Mirrors ArchivePasswordProvider: Core (the loader) calls the resolver when a
//  split archive needs read access to its containing folder (so sibling volumes
//  are readable); the app/UI fulfills it — prompting is the app's job. Given a file
//  in the set, return whether the folder is now accessible.
//

import Foundation

public typealias ArchiveFolderAccessResolver = @Sendable (URL) async -> Bool

public typealias ArchiveFolderAccessUserProvider = @Sendable (URL) async -> Bool
