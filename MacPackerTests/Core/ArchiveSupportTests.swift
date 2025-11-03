//
//  ArchiveSupportTests.swift
//  MacPacker
//
//  Created by Stephan Arenswald on 01.11.25.
//

import Testing
@testable import MacPacker
import UniformTypeIdentifiers

@Suite("Archive Support Tests") struct ArchiveSupportTests {
    let testBase: ArchiveTestBase = ArchiveTestBase()
    
    @Test func verify7zByExtension() throws {
        let url = try testBase.getTestFile(name: "defaultContent.7z")
        
        let detector = ArchiveTypeDetector()
        let result = detector.detectByExtension(for: url)
        
        #expect(result?.source == .fileExtension)
        #expect(result?.type.id == .`7zip`)
        #expect(result?.type.uti == UTType(importedAs: "org.7-zip.7-zip-archive"))
    }
    
    @Test func verify7zByMagicNumber() throws {
        let url = try testBase.getTestFile(name: "defaultContent.7z")
        
        let detector = ArchiveTypeDetector()
        let result = detector.detectByMagicNumber(for: url)
        
        #expect(result?.source == .magic)
        #expect(result?.type.id == .`7zip`)
        #expect(result?.type.uti == UTType(importedAs: "org.7-zip.7-zip-archive"))
    }
    
    @Test func verifyZipByExtension() throws {
        let url = try testBase.getTestFile(name: "defaultArchive.zip")
        
        let detector = ArchiveTypeDetector()
        let result = detector.detectByExtension(for: url)
        
        #expect(result?.source == .fileExtension)
        #expect(result?.type.id == .zip)
        #expect(result?.type.uti == UTType.zip)
    }
    
    @Test func verifyZipByMagicNumber() throws {
        let url = try testBase.getTestFile(name: "defaultArchive.zip")
        
        let detector = ArchiveTypeDetector()
        let result = detector.detectByMagicNumber(for: url)
        
        #expect(result?.source == .magic)
        #expect(result?.type.id == .zip)
        #expect(result?.type.uti == UTType.zip)
    }
    
    @Test func verifyXlsxAsZip() throws {
        let url = try testBase.getTestFile(name: "zipVariant.xlsx")
        
        let detector = ArchiveTypeDetector()
        let result = detector.detect(for: url)
        
        #expect(result?.source == .magic)
        #expect(result?.type.id == .zip)
        #expect(result?.type.uti == UTType.zip)
    }
    
    @Test func verifyIsoByMagicNumberWithOffset() throws {
        let url = try testBase.getTestFile(name: "defaultArchive.iso")
        
        let detector = ArchiveTypeDetector()
        let result = detector.detectByMagicNumber(for: url)
        
        #expect(result?.source == .magic)
        #expect(result?.type.id == .iso)
        #expect(result?.type.uti == UTType(importedAs: "public.iso-image"))
    }
    
    @Test func loadXadHandlerForZipFile() throws {
        let url = try testBase.getTestFile(name: "defaultArchive.zip")
        
        let detector = ArchiveTypeDetector()
        guard let result = detector.detectByExtension(for: url) else {
            return
        }
        
        let registry = ArchiveTypeRegistry.shared
        let handler = registry.handler(for: result.type.id)
        
        #expect(handler is ArchiveHandlerXad)
    }
}
