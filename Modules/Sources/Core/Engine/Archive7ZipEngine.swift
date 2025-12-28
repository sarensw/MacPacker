//
//  Archive7ZipEngine.swift
//  Modules
//
//  Created by Stephan Arenswald on 30.11.25.
//

import Foundation
import Subprocess
import System

final actor Archive7ZipEngine: ArchiveEngine {
    private var isCancelled: Bool = false
    
    private var statusContinuation: AsyncStream<EngineStatus>.Continuation?
    private lazy var status: AsyncStream<EngineStatus> = {
        AsyncStream(bufferingPolicy: .bufferingNewest(50)) { continuation in
            self.statusContinuation = continuation
            continuation.yield(.idle)
        }
    }()
    
    func statusStream() -> AsyncStream<EngineStatus> {
        AsyncStream { continuation in
            self.statusContinuation = continuation
            continuation.yield(.idle)
        }
    }
    
    private func emit(_ s: EngineStatus) {
        statusContinuation?.yield(s)
    }
    
    func cancel() {
        print("Archive7ZipEngine: Cancelling...")
        isCancelled = true
    }
    
    func readLines(from fd: FileDescriptor) throws -> [String] {
        // Rewind to start
        _ = try fd.seek(offset: 0, from: .start)

        var buffer = [UInt8](repeating: 0, count: 4096)
        var remainder = Data()
        var lines: [String] = []

        while true {
            let bytesRead = try buffer.withUnsafeMutableBytes { rawBuffer in
                try fd.read(into: rawBuffer)
            }

            if bytesRead == 0 { break }

            remainder.append(Data(buffer.prefix(bytesRead)))

            while let newlineRange = remainder.firstRange(of: Data([0x0A])) {
                let lineData = remainder[..<newlineRange.lowerBound]
                remainder.removeSubrange(..<newlineRange.upperBound)

                if let line = String(data: lineData, encoding: .utf8) {
                    lines.append(line)
                }
            }
        }

        // last line (no trailing newline)
        if !remainder.isEmpty,
           let line = String(data: remainder, encoding: .utf8) {
            lines.append(line)
        }

        return lines
    }
    
    private func checkCancellation() throws {
        if isCancelled || Task.isCancelled {
            emit(.cancelled)
            isCancelled = false
            throw CancellationError()
        }
    }
    
    func loadArchive(url: URL) async throws -> [ArchiveItem] {
        guard let cmdUrl = Bundle.module.url(forResource: "7zz", withExtension: nil) else {
            print("Failed to load 7zz exec")
            throw ArchiveError.loadFailed("Failed to load 7zz exec")
        }
        let path = FilePath(cmdUrl.path)
        var items: [ArchiveItem] = []
        
        emit(.processing(progress: nil, message: "running 7zz..."))
        
        let tempFileDescriptor = try ArchiveSupportUtilities().makeTempFileDescriptor()
        defer {
            do { try tempFileDescriptor.close() } catch {}
        }
        let _ = try await Subprocess.run(
            .path(path),
            arguments: ["l", url.path],
            output: .fileDescriptor(tempFileDescriptor, closeAfterSpawningProcess: false)
        ) { execution in
            if isCancelled {
                await execution.teardown(using: [
                    .send(signal: .kill, allowedDurationToNextStep: .seconds(0.1))
                ])
            }
        }
        
        try checkCancellation()
        
        emit(.processing(progress: nil, message: "7zz finished, start parsing..."))
        
        let lines = try readLines(from: tempFileDescriptor)

        try checkCancellation()
        
        var inBlock: Bool = false
        var i: Int = 0
        for line in lines {
            if line.starts(with: "-------------------") {
                inBlock.toggle()
            } else if inBlock {
                if let item = parse7zListLineFast(line.trimmingCharacters(in: .newlines)) {
                    items.append(item)
                }
            }
            
            if i % 1000 == 0 {
                try checkCancellation()
                
                emit(.processing(progress: Double(i) / Double(lines.count) * 100, message: "parsing..."))
            }
            i += 1
        }
        
        emit(.done)
        
        return items
    }
    
    func extract(item: ArchiveItem, from url: URL, to destination: URL) async throws -> URL? {
        guard let cmdUrl = Bundle.module.url(forResource: "7zz", withExtension: nil) else {
            Logger.error("Failed to load 7zz exec")
            throw ArchiveError.loadFailed("Failed to load 7zz exec")
        }
        guard let virtualPath = item.virtualPath else {
            Logger.error("No virtual path for item")
            return nil
        }
        let path = FilePath(cmdUrl.path)
        
        let args = [
            "e",
            url.path,
            "\(virtualPath)",
            "-o\(destination.path)",
            "-spf"
        ]
        
        Logger.log("""
            \(cmdUrl.path)
                \(args.reduce("", { $0 + $1 + "\n\t" }))
        """)
        
        print()
        print()
        let _ = try await Subprocess.run(
            .path(path),
            arguments: Arguments(args)
        ) { execution, standardOutput in
            if isCancelled {
                print("cancelled!!!")
                await execution.teardown(using: [])
            }
            var cnt = 0
            for try await line in standardOutput.lines() {
                cnt += 1
                print(line.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            print("\(cnt) items found")
        }
        print()
        print()
        
        let resultUrl = destination.appendingPathComponent(virtualPath)
        return resultUrl
    }
    
    func extract(_ url: URL, to destination: URL) async throws {
        let cmdPath = try getCommandFilePath()
        
        let args = [
            "e",
            url.path,
            "-o\(destination.path)",
            "-spf"
        ]
        
        Logger.log("""
            \(cmdPath)
                \(args.reduce("", { $0 + $1 + "\n\t" }))
        """)
        
        let _ = try await Subprocess.run(
            .path(cmdPath),
            arguments: Arguments(args)
        ) { execution, standardOutput in
            var cnt = 0
            for try await line in standardOutput.lines() {
                cnt += 1
                print(line.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            print("\(cnt) items found")
        }
    }
    
    private func getCommandFilePath() throws -> FilePath {
        guard let cmdUrl = Bundle.module.url(forResource: "7zz", withExtension: nil) else {
            Logger.error("Failed to load 7zz exec")
            throw ArchiveError.loadFailed("Failed to load 7zz exec")
        }
        return FilePath(cmdUrl.path)
    }
    
    private func parse7zListLineFast(_ line: String) -> ArchiveItem? {
        // 7z `l` layout (approx):
        // date(10) space time(8) space attrs(5) space size space compressed space path
        //          012345678901234567890123456789012345678901234567890123456789
        //          0         1         2         3         4         5
        // Example:
        // 2025-11-04 12:46:30 ..HS.    309592064    309592064  [SYSTEM]/$MFT
        //                     .....                            defaultArchive.tar
        
//        guard line.count > 43 else { return nil }
        
        let s = line
        let start = s.startIndex
        
        // attrs at ~20–25
        let attrStart = s.index(start, offsetBy: 20)
        let attrEnd   = s.index(attrStart, offsetBy: 5, limitedBy: s.endIndex) ?? s.endIndex
        let attrs     = s[attrStart..<attrEnd]
        let isDir = attrs.contains("D")
        
        // path at ~53+, skip leading spaces
        let pathStart = s.index(start, offsetBy: 53, limitedBy: s.endIndex) ?? s.endIndex
        let pathSub = s[pathStart...].drop(while: { $0 == " " })
        
        guard !pathSub.isEmpty else { return nil }
        let path = String(pathSub)
        
        // name = last path component
        let name: String
        if let idx = path.lastIndex(of: "/") {
            name = String(path[path.index(after: idx)...])
        } else {
            name = path
        }
        
        return ArchiveItem(
            name: name,
            virtualPath: path,
            type: isDir ? .directory : .file
        )
    }
}
