//
//  ArchiveHandlerSitTests.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 16.09.25.
//

import Foundation
import XCTest
@testable import MacPacker

final class ArchiveHandlerSitTests: XCTestCase {
    let testBase: ArchiveTestBase = ArchiveTestBase()
    let defaultTestFile: String = "testfile.stuffit7_dlx.macx1.sit"
    
    override class func setUp() {
        super.setUp()
        ArchiveTestBase().setUpPerClass()
    }
    
    override func setUp() {
        testBase.setUpPerTest()
    }
    
    func testLoadFile() throws {
        let tf = try testBase.getTestFile(name: defaultTestFile)
        
        let archive = try Archive2(url: tf)
        let count = archive.items.count
        XCTAssertEqual(count, 6)
    }
    
    func testExtractFile() throws {
        let tf = try testBase.getTestFile(name: defaultTestFile)
        
        let archive = try Archive2(url: tf)
        
        let url = archive.extractFileToTemp(archive.items[5])
        XCTAssertNotNil(url)
        
        let content = try String(contentsOf: url!, encoding: .utf8)
        XCTAssertTrue(content.starts(with:"Testing 123"))
    }
    
    func testExtractFullArchive() throws {
        let archive = try testBase.getArchiveFor(name: defaultTestFile)
        let service = ArchiveService()
        service.extract(
            archive: archive,
            to: ArchiveTestBase.tempDirectoryURL)
        print("Extracted to \(ArchiveTestBase.tempDirectoryURL)")
        
        XCTAssertTrue(testBase.fileExistsInTemp("Test Image"))
        XCTAssertTrue(testBase.fileExistsInTemp("Test Text"))
        XCTAssertTrue(testBase.fileExistsInTemp("testfile.jpg"))
        XCTAssertTrue(testBase.fileExistsInTemp("testfile.PICT"))
        XCTAssertTrue(testBase.fileExistsInTemp("testfile.png"))
        XCTAssertTrue(testBase.fileExistsInTemp("testfile.txt"))
    }
}
