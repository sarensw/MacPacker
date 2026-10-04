import ArchiveCommands
import Darwin
import Foundation
import Swift7zip

let help = """
MacPacker command-line interface
  macpacker list ARCHIVE [--ask-password | --password-stdin]
  macpacker extract ARCHIVE --output NEW_DIRECTORY [password option]
  macpacker create ARCHIVE INPUT... [--format 7z|zip|tar] [--volume-size 100m]
                   [password option] [--encrypt-names]
  macpacker update ARCHIVE INPUT... [password option]
  macpacker delete ARCHIVE ENTRY... [password option]
  macpacker rename ARCHIVE OLD_ENTRY NEW_ENTRY [password option]

Use -- before paths beginning with '-'. Passwords are never accepted as command
arguments. New archives and extraction directories must not already exist.
Exit codes: 0 success, 1 operation failed, 2 invalid arguments.
"""
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.isEmpty || arguments == ["--help"] || arguments == ["-h"] {
    print(help)
    exit(0)
}
let command: ArchiveCommand
do { command = try ArchiveCommand(arguments: arguments) }
catch { fputs("\(error.localizedDescription)\n\(help)\n", stderr); exit(2) }

do {
    let password: String?
    if command.askPassword {
        guard let raw = getpass("Archive password: ") else { throw CommandError("Could not read password from terminal.") }
        password = String(cString: raw)
        memset(raw, 0, strlen(raw))
    } else if command.passwordStdin {
        guard let line = readLine() else { throw CommandError("No password received on standard input.") }
        password = line
    } else { password = nil }
    try command.validatePassword(password)
    let manager = FileManager.default
    switch command.action {
    case .list:
        let archive = try SevenZipArchive(url: VolumePath.first(command.archive), password: password)
        for entry in try archive.entries { print("\(entry.size)\t\(entry.path)") }
    case .extract:
        try ArchiveExtraction.extract(command.archive, to: command.output!, password: password)
    case .create, .update, .delete, .rename:
        let creating = command.action == .create
        if !creating && VolumePath.first(command.archive) != command.archive { throw CommandError("Split archives cannot be edited in place.") }
        if creating && manager.fileExists(atPath: command.archive.path) { throw CommandError("The destination archive already exists.") }
        let archive = creating ? nil : try SevenZipArchive(url: VolumePath.first(command.archive), password: password)
        let entries = try archive?.entries ?? []
        var items: [ArchiveUpdateItem] = []
        switch command.action {
        case .create, .update:
            for operand in command.operands {
                let root = URL(fileURLWithPath: operand).standardizedFileURL
                guard manager.fileExists(atPath: root.path) else { throw CommandError("Input does not exist: \(operand)") }
                var urls = [root]
                if (try root.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true {
                    var enumerationError: Error?
                    guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], errorHandler: { _, error in
                        enumerationError = error
                        return false
                    }) else { throw CommandError("Cannot enumerate \(operand)") }
                    urls += enumerator.allObjects.compactMap { $0 as? URL }
                    if let enumerationError { throw enumerationError }
                }
                for url in urls {
                    let path = String(url.path.dropFirst(root.deletingLastPathComponent().path.count + 1))
                    items += entries.filter { $0.path == path }.map { .remove(sourceIndex: $0.index) }
                    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    if values.isDirectory == true && values.isSymbolicLink != true {
                        items.append(.addDirectory(archivePath: path, diskPath: url))
                    } else { items.append(.addFile(archivePath: path, diskPath: url)) }
                }
            }
        case .delete:
            for name in command.operands {
                let matches = entries.filter { $0.path == name || $0.path.hasPrefix(name + "/") }
                guard !matches.isEmpty else { throw CommandError("Entry not found: \(name)") }
                items += matches.map { .remove(sourceIndex: $0.index) }
            }
        case .rename:
            let old = command.operands[0], new = command.operands[1]
            guard !new.hasPrefix("/"), !new.split(separator: "/").contains(".."), !new.isEmpty else { throw CommandError("Invalid archive entry path.") }
            let matches = entries.filter { $0.path == old || $0.path.hasPrefix(old + "/") }
            guard !matches.isEmpty else { throw CommandError("Entry not found: \(old)") }
            for entry in matches {
                let target = new + entry.path.dropFirst(old.count)
                guard !entries.contains(where: { $0.path == target }) else { throw CommandError("Entry already exists: \(target)") }
                items.append(.move(sourceIndex: entry.index, newPath: target))
            }
        default: break
        }
        var options = CompressionOptions(format: command.format)
        options.password = creating ? password : nil
        options.encryptFileNames = command.encryptNames
        options.volumeSize = command.volumeSize
        try SevenZipArchive.writeArchive(source: creating ? nil : command.archive, destination: command.archive,
                                        items: items, options: options, sourcePassword: password)
    }
} catch {
    fputs("MacPacker: \(error.localizedDescription)\n", stderr)
    exit(1)
}
