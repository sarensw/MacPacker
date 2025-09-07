//
//  ArchiveHandlerLzxTests.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 07.09.25.
//

import Foundation
import XCTest
@testable import MacPacker

final class ArchiveHandlerLzxTests: XCTestCase {
    let testBase: ArchiveTestBase = ArchiveTestBase()
    
    override class func setUp() {
        super.setUp()
        ArchiveTestBase().setUpPerClass()
    }
    
    override func setUp() {
        testBase.setUpPerTest()
    }
    
    func testLoadLxz() throws {
        let tf = try testBase.getTestFile(name: "lzx_test_attrib_cmt.lzx")
        
        let archive = try Archive2(url: tf)
        let count = archive.items.count
        XCTAssertEqual(count, 1)
    }
    
    func testExtractFile() throws {
        let tf = try testBase.getTestFile(name: "lzx_test_attrib_cmt.lzx")
        
        let archive = try Archive2(url: tf)
        
        XCTAssertEqual(try archive.open(archive.items[0]), .success)
        if let se = archive.currentStackEntry {
            XCTAssertEqual(se.name, "LZX_Test")
        }
        
        let url = archive.extractFileToTemp(archive.items[2])
        XCTAssertNotNil(url)
        
        if let url {
            let content = try String(contentsOf: url, encoding: .isoLatin1)
            let startsWithEmpty = content.hasPrefix("Empty Directory 1")
            XCTAssertTrue(startsWithEmpty)
        }
    }
}

