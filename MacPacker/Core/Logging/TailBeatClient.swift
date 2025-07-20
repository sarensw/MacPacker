//
//  TailBeatClient.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 20.07.25.
//

import Foundation
import MachO
import Darwin
import Network
import UniformTypeIdentifiers

enum TailBeatLevel: String, Codable {
    case Trace
    case Debug
    case Info
    case Warning
    case Error
    case Fatal
}

struct TailBeatEvent: Codable, Identifiable {
    var id: UUID = UUID() // ✅ default value
    
    let timestamp: Date
    let level: TailBeatLevel
    let category: String
    let message: String
    let context: [String: String]?
    let file: String
    let function: String
    let line: Int
    
    private enum CodingKeys: String, CodingKey {
        case timestamp, level, category, message, context, file, function, line
        // intentionally exclude 'id'
    }
}

class TailBeat {
    // singleton instance
    static let logger = TailBeat()
    
    // network stuff
    private var connection: NWConnection?
    
    init(host: String = "127.0.0.1", port: UInt16 = 8085) {
        let params = NWParameters.tcp
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: params)
        connection?.start(queue: .global())
    }
    
    func log(level: TailBeatLevel = .Debug,
             category: String = "",
             _ message: String,
             context: [String: String]? = nil,
             file: String = #fileID,
             function: String = #function,
             line: Int = #line
    ) {
        #if DEBUG
        let log = TailBeatEvent(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            context: context,
            file: file,
            function: function,
            line: line
        )
        
        if let data = try? JSONEncoder().encode(log) {
            // TCP send or UDP send here
            connection?.send(content: data, completion: .contentProcessed { _ in })
        }
        #else
        print("\(Date.now.formatted(.omitted)) - \(level): \(message)")
        #endif
    }

    func getBinaryUUID() -> String? {
        // Get address of any symbol (use main)
        var info = Dl_info()
        if dladdr(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "main"), &info) == 0 {
            return nil
        }

        guard let imageHeader = info.dli_fbase?.assumingMemoryBound(to: mach_header_64.self) else {
            return nil
        }

        var cursor = UnsafeRawPointer(imageHeader).advanced(by: MemoryLayout<mach_header_64>.size)
        for _ in 0..<imageHeader.pointee.ncmds {
            let loadCommand = cursor.load(as: load_command.self)
            if loadCommand.cmd == LC_UUID {
                let uuidCmd = cursor.load(as: uuid_command.self)
                let uuidBytes = Mirror(reflecting: uuidCmd.uuid).children.map { $0.value as! UInt8 }
                let uuidString = uuidBytes.map { String(format: "%02X", $0) }.joined()
                
                // Format like Apple crash reports
                let formattedUUID = [
                    uuidString.prefix(8),
                    uuidString.dropFirst(8).prefix(4),
                    uuidString.dropFirst(12).prefix(4),
                    uuidString.dropFirst(16).prefix(4),
                    uuidString.dropFirst(20)
                ].map { String($0) }.joined(separator: "-")

                return formattedUUID
            }
            cursor = cursor.advanced(by: Int(loadCommand.cmdsize))
        }

        return nil
    }

}
