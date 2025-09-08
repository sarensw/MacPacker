//
//  ArchiveHandlerLhaLzhTests.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 07.09.25.
//

import Foundation
import XCTest
@testable import MacPacker

final class ArchiveHandlerLhaLzhTests: XCTestCase {
    let testBase: ArchiveTestBase = ArchiveTestBase()
    
    override class func setUp() {
        super.setUp()
        ArchiveTestBase().setUpPerClass()
    }
    
    override func setUp() {
        testBase.setUpPerTest()
    }
    
    func testLoadLhaLzh() throws {
        let tf = try testBase.getTestFile(name: "multiple.lzh")
        
        let archive = try Archive2(url: tf)
        let count = archive.items.count
        XCTAssertEqual(count, 5)
    }
    
    func testExtractFile() throws {
        let tf = try testBase.getTestFile(name: "multiple.lzh")
        
        let archive = try Archive2(url: tf)
        
        let url = archive.extractFileToTemp(archive.items[0])
        XCTAssertNotNil(url)
        
        if let url {
            let content = try String(contentsOf: url, encoding: .isoLatin1)
            let startsWith = content.hasPrefix("first file")
            XCTAssertTrue(startsWith)
        }
    }
    
    func testExtractFullArchive() throws {
        let archive = try testBase.getArchiveFor(name: "multiple.lzh")
        let service = ArchiveService()
        service.extract(
            archive: archive,
            to: ArchiveTestBase.tempDirectoryURL)
        print("Extracted to \(ArchiveTestBase.tempDirectoryURL)")
        
        XCTAssertTrue(testBase.fileExistsInTemp("file1.txt"))
        XCTAssertTrue(testBase.fileExistsInTemp("file2-1.txt"))
        XCTAssertTrue(testBase.fileExistsInTemp("file2-2.txt"))
        XCTAssertTrue(testBase.fileExistsInTemp("file3.txt"))
        XCTAssertTrue(testBase.fileExistsInTemp("file4.txt"))
    }
}
