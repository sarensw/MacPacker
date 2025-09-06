//
//  ArchiveHandlerTarTests.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 05.09.25.
//

import Foundation
import XCTest
@testable import MacPacker

final class ArchiveHandlerTarTests: XCTestCase {
    let testBase: ArchiveTestBase = ArchiveTestBase()
    
    override class func setUp() {
        super.setUp()
        ArchiveTestBase().setUpPerClass()
    }
    
    override func setUp() {
        testBase.setUpPerTest()
    }
    
    func testLoadTar() throws {
        let tf = try testBase.getTestFile(name: "archive.tar")
        
        let archive = try Archive2(url: tf)
        let count = archive.items.count
        XCTAssertEqual(count, 2)
    }
    
    func testExtractFile() throws {
        let tf = try testBase.getTestFile(name: "archive.tar")
        
        let archive = try Archive2(url: tf)
        let url = archive.extractFileToTemp(archive.items[0])
        XCTAssertNotNil(url)
        
        let content = try String(contentsOf: url!, encoding: .utf8)
        XCTAssertEqual(content, "James Bond.\n")
    }
}


