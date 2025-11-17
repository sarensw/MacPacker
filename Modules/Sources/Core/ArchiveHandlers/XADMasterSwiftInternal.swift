//
//  XADMasterSwiftInternal.swift
//  MacPacker
//
//  This is a copy of the XADMasterSwift file from the XADMasterSwift
//  repo. The difference is that there is no cache for the currently
//  active archive. From MacPacker point-of-view a handler is stateless.
//
//  Created by Stephan Arenswald on 06.09.25.
//

import Foundation
import XADMaster

public class XADMasterSwiftInternal {
    public static func extractArchive(at path: String, to destination: String) throws {
        guard let archive = XADArchive(file: path) else {
            throw NSError(domain: "XADMasterSwift", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create archive"])
        }
        archive.setNameEncoding(NSUTF8StringEncoding)
        archive.extract(to: destination)
    }

    public static func listContents(of path: String) throws -> [String] {
        guard let archive = XADArchive(file: path) else {
            throw NSError(domain: "XADMasterSwift", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create archive"])
        }
        archive.setNameEncoding(NSUTF8StringEncoding)

        if archive.isEncrypted() && archive.password()!.isEmpty {
            throw NSError(domain: "XADMasterSwift", code: 2, userInfo: [NSLocalizedDescriptionKey: "Password required"])
        }

        var contents: [String] = []
        for index in 0..<archive.numberOfEntries() {
            if let name = archive.name(ofEntry: index) {
                contents.append(name)
            }
        }
        return contents
    }

    public static func extractFile(at path: String, entryIndex: Int, to destination: String) throws {
        guard let archive = XADArchive(file: path) else {
            throw NSError(domain: "XADMasterSwift", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create archive"])
        }
        archive.setNameEncoding(NSUTF8StringEncoding)

        archive.extractEntry(Int32(entryIndex), to: destination)
    }

    public static func setPassword(for path: String, password: String) throws {
        guard let archive = XADArchive(file: path) else {
            throw NSError(domain: "XADMasterSwift", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create archive"])
        }
        archive.setNameEncoding(NSUTF8StringEncoding)

        archive.setPassword(password)
    }

    public static func getArchiveFormat(of path: String) throws -> String {
        guard let archive = XADArchive(file: path) else {
            throw NSError(domain: "XADMasterSwift", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create archive"])
        }
        archive.setNameEncoding(NSUTF8StringEncoding)

        return archive.formatName()
    }
}
