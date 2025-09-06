//
//  ArchiveHandlerZipTests.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 05.09.25.
//


import Foundation
import XCTest
@testable import MacPacker

final class ArchiveHandlerZipTests: XCTestCase {
    let testBase: ArchiveTestBase = ArchiveTestBase()
    
    override class func setUp() {
        super.setUp()
        ArchiveTestBase().setUpPerClass()
    }
    
    override func setUp() {
        testBase.setUpPerTest()
    }
    
    func testLoadTar() throws {
        let tf = try testBase.getTestFile(name: "archive.zip")
        
        let archive = try Archive2(url: tf)
        let count = archive.items.count
        XCTAssertEqual(count, 2)
    }
    
    func testExtractFile() throws {
        let tf = try testBase.getTestFile(name: "archive.zip")
        
        let archive = try Archive2(url: tf)
        let url = archive.extractFileToTemp(archive.items[0])
        XCTAssertNotNil(url)
        
        let content = try String(contentsOf: url!, encoding: .utf8)
        XCTAssertEqual(content, "James Bond.\n")
    }
    
    func testExtractNestedFile() throws {
        let tf = try testBase.getTestFile(name: "archiveNested1.zip")
        
        let archive = try Archive2(url: tf)
        XCTAssertEqual(try archive.open(archive.items[0]), .success)
        if let se = archive.currentStackEntry {
            XCTAssertEqual(se.name, "Folder")
        }

        XCTAssertEqual(try archive.open(archive.items[1]), .success)
        if let se = archive.currentStackEntry {
            XCTAssertEqual(se.name, "archive.tar.lz4")
        }
        XCTAssertEqual(try archive.open(archive.items[1]), .success)
        if let se = archive.currentStackEntry {
            XCTAssertEqual(se.name, "archive.tar")
        }
        XCTAssertEqual(try archive.open(archive.items[1]), .success)
        if let se = archive.currentStackEntry {
            XCTAssertEqual(se.name, "archive.tar")
        }
        
        let url = archive.extractFileToTemp(archive.items[1])
        XCTAssertNotNil(url)
        
        if let url {
            let content = try String(contentsOf: url, encoding: .utf8)
            XCTAssertEqual(content, "James Bond.\n")
        }
    }
}
