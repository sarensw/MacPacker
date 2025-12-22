//
//  ArchiveEngine.swift
//  Modules
//
//  Created by Stephan Arenswald on 25.11.25.
//

import Foundation

/// An engine has the knowledge on how a library, CLI tool, or anything else
/// can extract certain formats. Examples would be the `XADMaster` library
/// that is included as an SPM package. Or the `7zip` CLI tool. An engine
/// is stateless and has no idea about UI or logic. It always takes a url to stay stateless.
public protocol ArchiveEngine: Sendable {
    /// Loads the given archive to retrieve all entries (in form of `ArchiveItem`)
    /// - Parameter url: url of the archive
    /// - Returns: list of all entries
    func loadArchive(url: URL, loadCountUpdated: @MainActor @Sendable (Int) -> Void) async throws -> [ArchiveItem]
    
    /// Extracts the given item from the given archive to a temporary location
    /// - Parameters:
    ///   - item: item to extract
    ///   - from: archive url to extract the item from
    ///   - to: destination folder
    /// - Returns: the URL of the extracted item
    func extract(item: ArchiveItem, from url: URL, to destination: URL) async throws -> URL?
    
    /// Extracts the full archive to the given destination
    /// - Parameters:
    ///   - url: url of the archive to be extracted
    ///   - destination: destination folder
    func extract(_ url: URL, to destination: URL) async throws
}
