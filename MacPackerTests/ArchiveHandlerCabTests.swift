//
//  ArchiveHandlerCabTests.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 16.09.25.
//

import Foundation
import XCTest
@testable import MacPacker

final class ArchiveHandlerCabTests: XCTestCase {
    let testBase: ArchiveTestBase = ArchiveTestBase()
    let defaultTestFile: String = "absolute1.cab"
    
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
        XCTAssertEqual(count, 1)
    }
    
    func testExtractFile() throws {
        let tf = try testBase.getTestFile(name: defaultTestFile)
        
        let archive = try Archive2(url: tf)
        
        XCTAssertEqual(try archive.open(archive.items[0]), .success)
        if let se = archive.currentStackEntry {
            XCTAssertEqual(se.name, "tmp")
        }

        let url = archive.extractFileToTemp(archive.items[1])
        XCTAssertNotNil(url)
        
        let content = try String(contentsOf: url!, encoding: .utf8)
        XCTAssertEqual(content, "moo\n")
    }
    
    func testExtractFullArchive() throws {
        let archive = try testBase.getArchiveFor(name: defaultTestFile)
        let service = ArchiveService()
        service.extract(
            archive: archive,
            to: ArchiveTestBase.tempDirectoryURL)
        print("Extracted to \(ArchiveTestBase.tempDirectoryURL)")
        
        XCTAssertTrue(testBase.fileExistsInTemp("tmp/moo"))
    }
}
