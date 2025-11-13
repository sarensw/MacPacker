//
//  ArchiveHandlerP7Zip.swift
//  MacPackerCore
//
//  Created by Stephan Arenswald on 13.11.25.
//

import Foundation

public class ArchiveHandlerP7Zip: ArchiveHandler {
    
    public static func register() {
        let handler = ArchiveHandlerP7Zip()
        
        let typeRegistry = ArchiveTypeRegistry.shared
        
        typeRegistry.register(typeID: .zip, capabilities: [.view, .extract], handler: handler)
        typeRegistry.register(typeID: .vhdx, capabilities: [.view, .extract], handler: handler)
    }
    
    public static func binaryURL() throws -> URL {
        let p = Bundle.main.path(forAuxiliaryExecutable: "7zz")
        let a = Bundle.main.bundleURL
        Bundle.allBundles.forEach { print($0.bundleURL) }
        guard let url = Bundle.main.url(forResource: "7zz", withExtension: nil) else {
            print("Failed to load 7zz exec")
            throw ArchiveError.loadFailed("Failed to load 7zz exec")
        }
        return url
    }
    
    public override func contents(
        of url: URL
    ) throws -> [ArchiveItem] {
        let execUrl = try Self.binaryURL()
        let process = Process()
        process.executableURL = execUrl
        process.arguments = ["l", "-slt", url.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe   // capture errors too

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            
            print(output)
            
            let entries = parse7zSltOutput(output)
            return entries
        } else {
            print("Could not decode output.")
        }
        
        return []
    }
    
    // MARK: - SLT parser

    public func parse7zSltOutput(_ output: String) -> [ArchiveItem] {
        var items: [ArchiveItem] = []
        var currentProps: [String: String] = [:]
        var index = 0

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        func commitCurrent() {
            guard let path = currentProps["Path"], !path.isEmpty else {
                currentProps.removeAll()
                return
            }

            guard let folderFlag = currentProps["Folder"] else {
                // Likely header/footer block; skip
                currentProps.removeAll()
                return
            }

            let isFolder = (folderFlag == "+")
            let type: ArchiveItemType = isFolder ? .directory : .file

            // Path like "folder/NestedArchive.zip" or "hello world.txt"
            let pathComponents = path.split(separator: "/").map(String.init)
            let name = pathComponents.last ?? path
            let virtualPath: String? =
                pathComponents.count > 1 ? pathComponents.joined(separator: "/") : nil

            // Sizes
            let uncompressedSize = Int(currentProps["Size"] ?? "0") ?? 0
            let compressedSize = Int(currentProps["Packed Size"] ?? "0") ?? 0

            // Date
            let modificationDate: Date?
            if let modifiedStr = currentProps["Modified"], !modifiedStr.isEmpty {
                modificationDate = dateFormatter.date(from: modifiedStr)
            } else {
                modificationDate = nil
            }

            // Posix permissions (optional; may be octal)
            var posixPermissions: Int? = nil
            if let posixStr = currentProps["PosixAttrib"] ?? currentProps["PosixAttributes"],
               !posixStr.isEmpty {
                posixPermissions = Int(posixStr, radix: 8)
            }

            let item = ArchiveItem(
                index: index,
                name: name,
                virtualPath: virtualPath,
                type: type,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                modificationDate: modificationDate,
                posixPermissions: posixPermissions
            )

            items.append(item)
            index += 1
            currentProps.removeAll()
        }

        // Iterate over all lines
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // New entry starts here: commit the previous one first
            if trimmed.hasPrefix("Path = ") {
                if !currentProps.isEmpty {
                    commitCurrent()
                }
            }

            // Parse "Key = Value"
            let parts = trimmed.split(separator: "=", maxSplits: 1)
                .map { String($0).trimmingCharacters(in: .whitespaces) }

            guard parts.count == 2 else { continue }
            currentProps[parts[0]] = parts[1]
        }

        // Commit the last entry (e.g. "hello world.txt")
        if !currentProps.isEmpty {
            commitCurrent()
        }

        return items
    }
    
    // MARK: - Helpers

    private func splitIntoBlocks(_ output: String) -> [String] {
        var blocks: [String] = []
        var currentLines: [String] = []
        
        for line in output.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !currentLines.isEmpty {
                    blocks.append(currentLines.joined(separator: "\n"))
                    currentLines.removeAll()
                }
            } else {
                currentLines.append(line)
            }
        }
        
        if !currentLines.isEmpty {
            blocks.append(currentLines.joined(separator: "\n"))
        }
        
        return blocks
    }

    private func parseKeyValueBlock(_ block: String) -> [String: String] {
        var dict: [String: String] = [:]
        
        for line in block.components(separatedBy: .newlines) {
            // Expect format: "Key = Value"
            let parts = line.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            dict[parts[0]] = parts[1]
        }
        
        return dict
    }
}
