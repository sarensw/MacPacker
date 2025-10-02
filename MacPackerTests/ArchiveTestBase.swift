//
//  ArchiveTestBase.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 05.09.25.
//


import Foundation
import XCTest
@testable import MacPacker

final class ArchiveTestBase {
    static var tempDirectoryURL: URL = {
        let processInfo = ProcessInfo.processInfo
        var tempZipDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        tempZipDirectory.appendPathComponent("mptemp")
        // We use a unique path to support parallel test runs via
        // "swift test --parallel"
        // When using --parallel, setUp() and tearDown() are called
        // multiple times.
        tempZipDirectory.appendPathComponent(processInfo.globallyUniqueString)
        return tempZipDirectory
    }()
    
    func setUpPerClass() {
        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: ArchiveTestBase.tempDirectoryURL.absoluteString) {
                try fileManager.removeItem(at: ArchiveTestBase.tempDirectoryURL)
            }
            try fileManager.createDirectory(
                at: ArchiveTestBase.tempDirectoryURL,
                withIntermediateDirectories: true,
                attributes: nil)
        } catch {
            XCTFail("Unexpected error while trying to set up test resources.")
        }
    }
    
    func setUpPerTest() {
        let applicationSupportDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        if let url = applicationSupportDirectory {
            do {
                try FileManager.default.removeItem(at: url.appendingPathComponent("ta", conformingTo: .directory))
            } catch {
                Logger.error("Could not clear cache because...")
                Logger.error(error.localizedDescription)
            }
        }
    }
    
    func getTestFile(name: String) throws -> URL {
        // load all the test files
        guard let file = Bundle(for: type(of: self)).url(forResource: name, withExtension: nil) else {
            throw TestError.testError("\(name) not found")
        }
        return file
    }
    
    func getArchiveFor(name: String) throws -> Archive2 {
        let fileURL = try getTestFile(name: name)
        return try Archive2(url: fileURL)
    }
    
    func fileExistsInTemp(_ filename: String) -> Bool {
        let temp = ArchiveTestBase.tempDirectoryURL.appendingPathComponent(filename)
        let exists = FileManager.default.fileExists(atPath: temp.path)
        return exists
    }
}
