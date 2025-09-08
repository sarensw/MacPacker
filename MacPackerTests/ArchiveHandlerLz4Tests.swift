//
//  ArchiveHandlerLz4Tests.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 08.09.25.
//

import Foundation
import XCTest
@testable import MacPacker

final class ArchiveHandlerLz4Tests: XCTestCase {
    let testBase: ArchiveTestBase = ArchiveTestBase()
    
    override class func setUp() {
        super.setUp()
        ArchiveTestBase().setUpPerClass()
    }
    
    override func setUp() {
        testBase.setUpPerTest()
    }
    
    func testLoadArchive() throws {
        let archive = try testBase.getArchiveFor(name: "archive.tar.lz4")
        let count = archive.items.count
        XCTAssertEqual(count, 1)
    }
    
    func testExtractFile() throws {
        let archive = try testBase.getArchiveFor(name: "archive.tar.lz4")
        let service = ArchiveService()
        service.extract(
            archive: archive,
            items: [archive.items[0]],
            to: ArchiveTestBase.tempDirectoryURL)
        
        XCTAssertTrue(testBase.fileExistsInTemp("archive.tar"))
    }
    
    func testExtractFullArchive() throws {
        let tempUrl = ArchiveTestBase.tempDirectoryURL
        let archive = try testBase.getArchiveFor(name: "archive.tar.lz4")
        let service = ArchiveService()
        service.extract(
            archive: archive,
            to: tempUrl)
        
        XCTAssertTrue(testBase.fileExistsInTemp("archive.tar"))
        
        let archiveTar = try Archive2(url: tempUrl.appending(components: "archive.tar"))
        service.extract(
            archive: archiveTar,
            to: tempUrl)
        
        XCTAssertTrue(testBase.fileExistsInTemp("bond.txt"))
        XCTAssertTrue(testBase.fileExistsInTemp("hello.txt"))
    }
}
