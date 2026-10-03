import Foundation
import Swift7zip

/// Shell-independent command parsing shared by the executable and its tests.
public struct ArchiveCommand: Sendable {
    public enum Action: String, Sendable { case list, extract, create, update, delete, rename }
    public var action: Action
    public var archive: URL
    public var operands: [String]
    public var output: URL?
    public var format: CompressionOptions.Format
    public var volumeSize: UInt64?
    public var askPassword = false
    public var passwordStdin = false
    public var encryptNames = false

    public init(arguments: [String]) throws {
        guard let first = arguments.first, let action = Action(rawValue: first) else {
            throw CommandError("Expected list, extract, create, update, delete, or rename.")
        }
        self.action = action
        var positional: [String] = []
        var formatName: String?
        var index = 1
        var literal = false
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            func value() throws -> String {
                guard index < arguments.count else { throw CommandError("Missing value for \(argument).") }
                defer { index += 1 }
                return arguments[index]
            }
            if literal { positional.append(argument); continue }
            switch argument {
            case "--": literal = true
            case "--output": output = URL(fileURLWithPath: try value())
            case "--format": formatName = try value()
            case "--volume-size": volumeSize = try Self.bytes(try value())
            case "--ask-password": askPassword = true
            case "--password-stdin": passwordStdin = true
            case "--encrypt-names": encryptNames = true
            default:
                guard !argument.hasPrefix("-") else { throw CommandError("Unknown option: \(argument)") }
                positional.append(argument)
            }
        }
        guard let path = positional.first else { throw CommandError("An archive path is required.") }
        archive = URL(fileURLWithPath: path)
        operands = Array(positional.dropFirst())
        guard let format = CompressionOptions.Format(rawValue: formatName ?? archive.pathExtension.lowercased()) ?? (action == .list || action == .extract ? .sevenZ : nil) else {
            throw CommandError("Unsupported output format. Choose 7z, zip, or tar.")
        }
        self.format = format
        guard !(askPassword && passwordStdin) else { throw CommandError("Choose one password input method.") }
        guard action == .create || volumeSize == nil else { throw CommandError("Volumes can only be created as a new archive.") }
        guard !encryptNames || format == .sevenZ else { throw CommandError("Encrypted names require 7z.") }
        if action == .extract && output == nil { throw CommandError("Extraction requires --output DIRECTORY.") }
        if [.create, .update, .delete].contains(action) && operands.isEmpty { throw CommandError("This command requires input paths or entry names.") }
        if action == .rename && operands.count != 2 { throw CommandError("Rename requires the old and new entry paths.") }
        if [.list, .extract].contains(action) && !operands.isEmpty { throw CommandError("Unexpected extra arguments.") }
        if action != .extract && output != nil { throw CommandError("--output is only for extraction.") }
    }

    public static func bytes(_ text: String) throws -> UInt64 {
        var digits = text.lowercased()
        let suffixes: [Character: UInt64] = ["k": 1 << 10, "m": 1 << 20, "g": 1 << 30]
        let multiplier = digits.last.flatMap { suffixes[$0] } ?? 1
        if multiplier != 1 { digits.removeLast() }
        guard let number = UInt64(digits), number > 0 else { throw CommandError("Invalid volume size: \(text)") }
        let result = number.multipliedReportingOverflow(by: multiplier)
        guard !result.overflow else { throw CommandError("Volume size is too large.") }
        return result.partialValue
    }
}

public struct CommandError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
