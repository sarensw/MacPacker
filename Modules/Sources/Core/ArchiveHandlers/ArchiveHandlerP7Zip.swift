////
////  ArchiveHandlerP7Zip.swift
////  MacPackerCore
////
////  Created by Stephan Arenswald on 13.11.25.
////
//
//import Foundation
//
//private enum Sections {
//    case header
//    case block
//    case blockBreak
//    case footer
//    case table
//}
//
//extension Date {
//    func printNowWithMs(_ prefix: String = "") {
//        let preferredFormat = Date.FormatStyle()
//            .weekday(.abbreviated)
//            .month(.twoDigits)
//            .day(.twoDigits)
//            .year()
//            .hour()
//            .minute()
//            .second(.twoDigits)
//            .secondFraction(.fractional(3))
//            .timeZone(.iso8601(.short))
//            .locale(.init(identifier: "US"))
//        
//        print("\(prefix): \(self.formatted(preferredFormat))")
//    }
//}
//
//public class InternalProcess {
//    public enum InternalProcessCommand {
//        case `7zz`
//    }
//    
//    public func launch(command: InternalProcessCommand, args: [String]) throws -> Data {
//        let process = Process()
//        process.executableURL = try binaryURL()
//        process.arguments = args
//        
//        let stdout = Pipe()
//        
//        process.standardOutput = stdout
//        
//        var outputData: Data = Data()
//        
//        let Q = DispatchQueue(label: "shell")
//        
//        // read all the output from the command
//        stdout.fileHandleForReading.readabilityHandler = { handle in
//            let data = handle.availableData
//            Q.async { outputData.append(data) }
//        }
//        
//        try process.run()
//        process.waitUntilExit()
//        
//        return Q.sync {
//            return outputData
//        }
//    }
//    
//    private func binaryURL() throws -> URL {
//        guard let url = Bundle.main.url(forResource: "7zz", withExtension: nil) else {
//            print("Failed to load 7zz exec")
//            throw ArchiveError.loadFailed("Failed to load 7zz exec")
//        }
//        return url
//    }
//}
//
//public class ArchiveHandlerP7Zip: ArchiveHandler {
//    private let listLineRegex = /^(?<date>\d{4}-\d{2}-\d{2})\s+(?<time>\d{2}:\d{2}:\d{2})\s+(?<permissions>[A-Z\.]{5})\s+(?<size>\d*)\s+(?<compressed>\d*)\s+(?<path>.+)$/
//
//    public static func register() {
//        let handler = ArchiveHandlerP7Zip()
//        
//        let typeRegistry = ArchiveTypeRegistry.shared
//        
//        typeRegistry.register(typeID: .zip, capabilities: [.view, .extract], handler: handler)
//        typeRegistry.register(typeID: .vhdx, capabilities: [.view, .extract], handler: handler)
//        typeRegistry.register(typeID: .ntfs, capabilities: [.view, .extract], handler: handler)
//    }
//    
//    public func contents2(
//        of url: URL
//    ) throws -> [ArchiveItem] {
//        var items: [ArchiveItem] = []
//        var section: Sections = .header
//        Date.now.printNowWithMs("1")
//        let data = try InternalProcess().launch(command: .`7zz`, args: ["l", url.path])
//        Date.now.printNowWithMs("2")
//        let output = String(data: data, encoding: .utf8)!
//        Date.now.printNowWithMs("2.1")
//        
//        var cnt = 0
//        output.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).forEach { line in
//            if section == .table {
//                if let item = parse7zListLineFast(line) {
////                if let item = parse7zLOutputLine(String(line)) {
//                    items.append(item)
//                    cnt += 1
//                }
//            } else {
//                if line.hasPrefix("-------------------") {
//                    section = .table
//                }
//            }
//        }
//        Date.now.printNowWithMs("3")
//        print(cnt)
//        
//        return items
//    }
//    
//    public func contents3(of url: URL) throws -> [ArchiveItem] {
//        Date.now.printNowWithMs("1")
//        let data = try InternalProcess().launch(command: .`7zz`, args: ["l", url.path])
//        Date.now.printNowWithMs("2")
//
//        let output = String(data: data, encoding: .utf8)!
//        Date.now.printNowWithMs("2.1")
//
//        // 1) Split into lines once
//        let lines = output.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
//
//        // 2) Find the start of the table (the line *after* the dashes)
//        var tableStartIndex: Int? = nil
//        for (idx, line) in lines.enumerated() {
//            if line.hasPrefix("-------------------") {
//                tableStartIndex = idx + 1
//                break
//            }
//        }
//
//        guard let startIdx = tableStartIndex else {
//            Date.now.printNowWithMs("3 (no table)")
//            return []
//        }
//
//        let tableLines = lines[startIdx..<lines.count]
//        let lineCount = tableLines.count
//
//        // Pre-size output for fewer reallocations
//        var items: [ArchiveItem] = []
//        items.reserveCapacity(lineCount)   // upper bound; most lines are entries
//
//        // 3) Parse tableLines in parallel
//        let cpuCount = ProcessInfo.processInfo.activeProcessorCount
//        let workerCount = min(cpuCount, max(1, lineCount))
//
//        // Each worker will store its own local items to avoid lock contention
//        var partialResults = Array(repeating: [ArchiveItem](), count: workerCount)
//        let partialLock = NSLock() // only needed to store partials back safely
//
//        DispatchQueue.concurrentPerform(iterations: workerCount) { worker in
//            let start = lineCount * worker / workerCount
//            let end   = lineCount * (worker + 1) / workerCount
//            if start >= end { return }
//
//            var local: [ArchiveItem] = []
//            local.reserveCapacity(end - start)
//
//            var idx = tableLines.index(tableLines.startIndex, offsetBy: start)
//            for _ in start..<end {
//                let line = tableLines[idx]
//                if let item = self.parse7zListLineFast(line) {
//                    local.append(item)
//                }
//                tableLines.formIndex(after: &idx)
//            }
//
//            partialLock.lock()
//            partialResults[worker] = local
//            partialLock.unlock()
//            Date.now.printNowWithMs("\(worker) done (doing \(end - start) lines)")
//        }
//
//        // 4) Flatten partial results
//        for chunk in partialResults {
//            items.append(contentsOf: chunk)
//        }
//
//        Date.now.printNowWithMs("3")
//        print(items.count)
//        return items
//    }
//    
//    public override func contents(of url: URL) throws -> [ArchiveItem] {
//        Date.now.printNowWithMs("1")
//        let data = try InternalProcess().launch(command: .`7zz`, args: ["l", url.path])
//        Date.now.printNowWithMs("2")
//
//        var items: [ArchiveItem] = []
//        data.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
//            let buffer = rawBuffer.bindMemory(to: UInt8.self)
//            items = parse7zListBuffer(buffer)
//        }
//
//        Date.now.printNowWithMs("3")
//        print(items.count)
//        return items
//    }
//
//
//    
//    // MARK: - SLT parser
//    
//    private func parse7zListBuffer(_ buf: UnsafeBufferPointer<UInt8>) -> [ArchiveItem] {
//        var items: [ArchiveItem] = []
//        items.reserveCapacity(300_000) // rough guess; adjust if you know more
//
//        let newline: UInt8 = 10 // '\n'
//        let carriageReturn: UInt8 = 13 // '\r'
//        var inTable = false
//
//        var i = 0
//        let end = buf.count
//
//        while i < end {
//            let lineStart = i
//
//            // find end of line
//            while i < end && buf[i] != newline && buf[i] != carriageReturn {
//                i += 1
//            }
//            let lineEnd = i
//
//            // skip newline characters (\r, \n, or both)
//            while i < end && (buf[i] == newline || buf[i] == carriageReturn) {
//                i += 1
//            }
//
//            let lineLength = lineEnd - lineStart
//            if lineLength <= 0 { continue }
//
//            if !inTable {
//                if isDashLine(buf, from: lineStart, to: lineEnd) {
//                    inTable = true
//                }
//                continue
//            }
//
//            if let item = parse7zListLineBytes(buf, from: lineStart, to: lineEnd) {
//                items.append(item)
//            }
//        }
//
//        return items
//    }
//    
//    private func isDashLine(_ buf: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int) -> Bool {
//        // 7z prints a line like "------------------- ----- ------------ ..."
//        // For our purposes it's enough to check first N chars are '-'
//        var i = start
//        var dashCount = 0
//        while i < end {
//            if buf[i] == UInt8(ascii: "-") {
//                dashCount += 1
//                if dashCount >= 10 { return true } // arbitrary, but cheap
//            } else {
//                break
//            }
//            i += 1
//        }
//        return false
//    }
//
//    private func parse7zListLineBytes(
//        _ buf: UnsafeBufferPointer<UInt8>,
//        from start: Int,
//        to end: Int
//    ) -> ArchiveItem? {
//
//        // Skip non-entry lines quickly: must start with digit
//        let first = buf[start]
//        if first < UInt8(ascii: "0") || first > UInt8(ascii: "9") {
//            return nil
//        }
//
//        let length = end - start
//        if length <= 53 { return nil } // path roughly starts around there
//
//        // Layout reminder:
//        // 0-9:  date "YYYY-MM-DD"
//        // 10:   space
//        // 11-18: time "HH:MM:SS"
//        // 19:   space
//        // 20-24: attrs (5 chars)
//        // 25:   space
//        // ...   some spaces, size, more spaces, compressed, spaces, path
//
//        // permissions / attrs
//        let attrStart = start + 20
//        let attrEnd = attrStart + 5
//        var isDir = false
//        if attrEnd <= end {
//            var j = attrStart
//            while j < attrEnd {
//                if buf[j] == UInt8(ascii: "D") {
//                    isDir = true
//                    break
//                }
//                j += 1
//            }
//        }
//
//        // path: we know it's somewhere after column ~53, so start there
//        var pathStart = start + 53
//        if pathStart > end { return nil }
//
//        // skip spaces between columns and path
//        while pathStart < end && buf[pathStart] == UInt8(ascii: " ") {
//            pathStart += 1
//        }
//        if pathStart >= end { return nil }
//
//        let pathLength = end - pathStart
//        if pathLength <= 0 { return nil }
//
//        // Create String from the utf8 slice (this is the only allocation per line)
//        let pathPtr = buf.baseAddress! + pathStart
//        let pathBytes = UnsafeBufferPointer(start: pathPtr, count: pathLength)
//        let path = String(decoding: pathBytes, as: UTF8.self)
//
//        return ArchiveItem(
//            name: "",
//            virtualPath: path,
//            type: isDir ? .directory : .file
//        )
//    }
//
//
//    
//    private func parse7zLOutputLine(_ line: String) -> ArchiveItem? {
//        if let result = line.wholeMatch(of: listLineRegex) {
//            let path = String(result.path)
//            let name: String
//            if let idx = path.lastIndex(of: "/") {
//                name = String(path[path.index(after: idx)...])
//            } else {
//                name = path
//            }
//            
//            let archiveItem = ArchiveItem(
//                name: name,
//                virtualPath: path,
//                type: .file
//            )
//            return archiveItem
//        }
//        
//        return nil
//    }
//    
//    private func parse7zListLineFast(_ line: Substring) -> ArchiveItem? {
//        // Skip non-entry lines quickly (e.g. summary/footer)
//        guard let first = line.first, first.isNumber else { return nil }
//
//        // 7z `l` layout (approx):
//        // date(10) space time(8) space attrs(5) space size space compressed space path
//        //          012345678901234567890123456789012345678901234567890123456789
//        //          0         1         2         3         4         5
//        // Example:
//        // 2025-11-04 12:46:30 ..HS.    309592064    309592064  [SYSTEM]/$MFT
//
//        guard line.count > 53 else { return nil }
//
//        let s = line
//        let start = s.startIndex
//
//        // attrs at ~20–25
//        let attrStart = s.index(start, offsetBy: 20)
//        let attrEnd   = s.index(attrStart, offsetBy: 5, limitedBy: s.endIndex) ?? s.endIndex
//        let attrs     = s[attrStart..<attrEnd]
//        let isDir = attrs.contains("D")
//
//        // path at ~53+, skip leading spaces
//        let pathStart = s.index(start, offsetBy: 53, limitedBy: s.endIndex) ?? s.endIndex
//        let pathSub = s[pathStart...].drop(while: { $0 == " " })
//
//        guard !pathSub.isEmpty else { return nil }
//        let path = String(pathSub)
//
//        // name = last path component
//        let name: String
//        if let idx = path.lastIndex(of: "/") {
//            name = String(path[path.index(after: idx)...])
//        } else {
//            name = path
//        }
//
//        return ArchiveItem(
//            name: name,
//            virtualPath: path,
//            type: isDir ? .directory : .file
//        )
//    }
//    
//    private func parse7zLOutput(_ output: String) -> [ArchiveItem] {
//        var items: [ArchiveItem] = []
//        var section: Sections = .header
//        let search = /^(?<date>\d{4}-\d{2}-\d{2})\s+(?<time>\d{2}:\d{2}:\d{2})\s+(?<permissions>[A-Z\.]{5})\s+(?<size>\d*)\s+(?<compressed>\d*)\s+(?<path>.+)$/
//        
//        let lines = output.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
//
//        for line in lines {
//            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
//            
//            if trimmed.hasPrefix("-------------------") {
//                section = .table
//                continue
//            }
//            
//            if section == .table {
//                if let result = line.wholeMatch(of: search) {
//                    let archiveItem = ArchiveItem(
//                        name: String(result.6),
//                        virtualPath: String(result.6),
//                        type: .file
//                    )
//                    items.append(archiveItem)
//                }
//            }
//        }
//        
//        return items
//    }
//
//    public func parse7zLSltOutput(_ output: String) -> [ArchiveItem] {
//        var items: [ArchiveItem] = []
//        var currentProps: [String: String] = [:]
//        var index = 0
//        var section: Sections = .header
//
//        let dateFormatter = DateFormatter()
//        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
//        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
//
//        // Iterate over all lines
//        let lines = output.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
//
//        for line in lines {
//            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
////            print(line)
//
//            if trimmed.hasPrefix("-------------------") {
//                section = .block
//                continue
//            }
//            
//            // two empty lines essentially means end of the blocks section
//            if section == .blockBreak {
//                if trimmed.isEmpty {
//                    section = .footer
//                } else {
//                    section = .block
//                }
//            }
//            
//            // we're still in the block section... parse whatever is here
//            if section == .block {
//                if trimmed.isEmpty {
//                    section = .blockBreak
//                    
//                    if let archiveItem = createArchiveItem(from: currentProps) {
//                        items.append(archiveItem)
//                    }
//                    
//                    currentProps.removeAll()
//                } else {
//                    if let keyValue = parseLine(trimmed) {
//                        currentProps[keyValue.key] = keyValue.value
//                    }
//                }
//            }
//        }
//
//        return items
//    }
//    
//    private func createArchiveItem(from block: [String: String]) -> ArchiveItem? {
//        
//        let path: String? = block["Path"]
//        let size: String? = block["Size"]
//        let fileSystem: String? = block["File System"]
//        let characteristics: String? = block["Characteristics"]
//        let offset: String? = block["Offset"]
//        let id: String? = block["ID"]
//        
//        guard let path else { return nil }
//        
//        let archiveItem = ArchiveItem(
//            name: path,
//            type: .file
//        )
//        
//        return archiveItem
//    }
//    
//    private func parseLine(_ line: String) -> (key: String, value: String)? {
//        let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
//        guard parts.count == 2 else { return nil }
//        return (String(parts[0].trimmingCharacters(in: .whitespacesAndNewlines)), String(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)))
//    }
//}
