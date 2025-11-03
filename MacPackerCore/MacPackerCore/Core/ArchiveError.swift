//
//  ArchiveError.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 06.09.25.
//


enum ArchiveError: Error {
    // used to say that the archive is invalid and cannot be extracted
    case invalidArchive(_ message: String)
}
