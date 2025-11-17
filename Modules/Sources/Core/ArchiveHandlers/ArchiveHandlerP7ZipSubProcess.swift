//
//  ArchiveHandlerP7ZipSubProcess.swift
//  MacPackerCore
//
//  Created by Stephan Arenswald on 17.11.25.
//

import Foundation
import Subprocess
import System

public class ArchiveHandlerP7ZipSubProcess: ArchiveHandler {
    public static func register() {
        let handler = ArchiveHandlerP7ZipSubProcess()
        
        let typeRegistry = ArchiveTypeRegistry.shared
        
        typeRegistry.register(typeID: .vhdx, capabilities: [.view, .extract], handler: handler)
        typeRegistry.register(typeID: .ntfs, capabilities: [.view, .extract], handler: handler)
    }
    
    private func binaryURL() throws -> URL {
        guard let url = Bundle.main.url(forResource: "7zz", withExtension: nil) else {
            print("Failed to load 7zz exec")
            throw ArchiveError.loadFailed("Failed to load 7zz exec")
        }
        return url
    }
    
    public override func contents(
        of url: URL
    ) throws -> [ArchiveItem] {
        guard let cmdUrl = Bundle.main.url(forResource: "7zz", withExtension: nil) else {
            print("Failed to load 7zz exec")
            throw ArchiveError.loadFailed("Failed to load 7zz exec")
        }
        let path = FilePath(cmdUrl.path)
        
        print(path)
        
        Date.now.printNowWithMs("1")
        Task {
            let process = try await Subprocess.run(
                .path(path),
                arguments: ["l", url.path]
            ) { execution, standardOutput in
                var cnt = 0
                for try await line in standardOutput.lines() {
                    cnt += 1
//                    print(line)
                }
                Date.now.printNowWithMs("2")
                print("\(cnt) items found")
            }
        }
        
        return []
    }
}
