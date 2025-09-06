//
//  Archive2.swift
//  MacPacker
//
//  Created by Arenswald, Stephan on 24.09.23.
//

import Foundation
import AppKit

enum Archive2Error: Error {
    case unknownType(String)
    case nonEditable(String)
}

enum Archive2OpenResult: String {
    case success = "success"
    case leaveDirectory = "leave"
}

/// Unused yet, but will be used in future to replace FileContainer
class Archive2: ObservableObject {
    @Published var url: URL?
    @Published var internalPath: String = "/"
    @Published var ext: String?
    @Published var stack: ArchiveItemStack = ArchiveItemStack()
    @Published public var items: [ArchiveItem] = []
    @Published var tempDirs: [URL] = []
    @Published var errorMessage: String?
    var currentStackEntry: ArchiveItemStackEntry? = nil
    private var breadcrumbsUpdated: (([String]) -> Void)?
    
    //
    // Initializers
    //
    
    /// Default constructor
    init() {
        url = nil
        breadcrumbsUpdated = { _ in }
    }
    
    /// Constructor use if loading an archive. Used for testing only
    /// - Parameter url: url to load
    /// - Throws: Throws Archive2Error.unknownType in case the archive type is unknown
    init(url: URL) throws {
        self.url = url
        determineFileExtension(from: url)
        if let ext,
           !ArchiveHandlerRegistry.shared.isSupported(ext: ext) {
            throw Archive2Error.unknownType("Unknown archive type")
        }
        try load(url)
    }
    
    /// Constructor use if loading an archive
    /// - Parameter url: url to load
    /// - Parameter breadcrumbsUpdated: closure that is called whenever the archive path changes
    /// - Throws: Throws Archive2Error.unknownType in case the archive type is unknown
    init(url: URL, breadcrumbsUpdated: @escaping ([String]) -> Void) throws {
        self.breadcrumbsUpdated = breadcrumbsUpdated
        self.url = url
        determineFileExtension(from: url)
        if let ext,
           !ArchiveHandlerRegistry.shared.isSupported(ext: ext) {
            throw Archive2Error.unknownType("Unknown archive type")
        }
        try load(url)
    }
    
    //
    // Description
    //
    
    public var description: String {
        var result = "> \(String(describing: url))\n"
        result = result + "  ext: \(String(describing: ext))"
        return result
    }
    
    //
    // Functions
    //
    
    /// Cleans up all the temporary dirs created during the extraction process
    public func clean() throws {
        for tempDir in tempDirs {
            try FileManager.default.removeItem(at: tempDir)
        }
        tempDirs.removeAll()
    }
    
    /// Checks if the given file is a zip file. It does not check for the extension,
    /// but instead for the first header of the zip to determine this.
    /// - Parameter url: url of the file to check
    /// - Returns: true in case it is a valid zip file, false otherwise
    private func checkIfZipFile(url: URL) -> Bool {
        var result: Bool = false
        if let fh = FileHandle(forReadingAtPath: url.path) {
            let data = fh.readData(ofLength: 4)
            if data.starts(with: [0x50, 0x4b, 0x03, 0x04]) {
                // File starts with ZIP magic ...
                result = true
            }
            fh.closeFile()
        }
        return result
    }
    
    /// Determines the archive type based on the extension for the given file url
    /// - Parameter url: file url
    /// - Returns: archive type
    private func determineFileExtension(from url: URL) {
        if let ext = url.path.split(separator: ".").last {
            self.ext = String(ext)
        }
    }
    
    /// Adds the given files to the archive. Note that this only works for editable archives
    /// - Parameter urls: the urls of the files to add
    func add(urls: [URL]) throws {
        if let ext,
           let handler = ArchiveHandler.for(ext: ext),
           handler.isEditable {
            for url in urls {
                items.append(ArchiveItem(path: url, type: .file))
            }
        } else if ext == nil {
            for url in urls {
                items.append(ArchiveItem(path: url, type: .file))
            }
        } else {
            throw Archive2Error.nonEditable("Archive is not editable")
        }
    }
    
    /// Saves the current list of items to the given URL as an archvie
    /// - Parameter url: the url where to save the archive
    /// - Parameter ext: the archive extension, hence type to save the archive in
    func save(to url: URL, as ext: String) throws {
        // save the archive
        if let handler = ArchiveHandler.for(ext: ext),
           handler.isEditable {
            try handler.save(to: url, items: items)
        } else {
            throw Archive2Error.nonEditable("Archive is not editable")
        }
    }
    
    
    /// Loads the given stack entry. Whenever something happens in MacPacker,
    /// a stack entry is created which in turn is then loaded. A stack entry basically
    /// defines at what folder/archive to look at.
    /// - Parameters:
    ///   - entry: stack entry
    ///   - clear: true to clear the full stack
    ///   - push: true to push the entry on that stack
    private func loadStackEntry(_ entry: ArchiveItemStackEntry, clear: Bool = false, push: Bool = true) {
        do {
            // stack item is directory that actually exists
            if entry.archivePath == nil {
                try loadDirectoryContent(url: entry.localPath)
                print("enable this")
            }
            
            // stack item is archive
            if let archivePath = entry.archivePath,
               let archiveType = entry.archiveType,
               let handler = ArchiveHandler.for(ext: archiveType) {
//                let archive = try ArchiveType.with(archiveType)
                
                if let content: [ArchiveItem] = try? handler.content(
                    archiveUrl: entry.localPath,
                    archivePath: archivePath) {
                    
                    // sort the result
                    items = content.sorted {
                        if $0.type == $1.type {
                            return $0.name < $1.name
                        }
                        
                        return $0.type > $1.type
                    }
                    if (stack.count > 0 && push == true) || stack.count > 1 {
                        items.insert(ArchiveItem.parent, at: 0)
                    }
                }
            }
            
            // add the item to the stack and clear if requested
//            if clear { resetStack() }
            if push {
                stack.push(entry)
            }
            
            // update the breadcrumb with the current path
            var names = stack.names()
            if let last = stack.last() {
                names.insert(last.localPath.deletingLastPathComponent().path, at: 0)
            }
//            names[0] = stack.last()!.localPath.path
            breadcrumbsUpdated?(names)
            
            self.currentStackEntry = entry
        } catch {
            print(error)
        }
        
        Logger.log(stack.description)
    }
    
    /// Checks if the given archive extension is supported to be loaded in MacPacker
    /// - Parameter ext: extension
    /// - Returns: true in case supported, false otherwise
    public func isSupportedArchive(ext: String) -> Bool {
        return ArchiveHandlerRegistry.shared.isSupported(ext: ext)
    }
    
    /// Checks if the given path is a directory
    /// - Parameter path: path to the potential directory
    /// - Returns: true in case the path is a dir, false otherwise
    public func isDirectory(path: URL) throws -> Bool {
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory) {
            items = []
            throw CocoaError(.fileNoSuchFile)
        }
        
        return isDirectory.boolValue
    }
    
//    public func moveDirectoryUp(_ item: ArchiveItem) throws {
//        // let's use completePath to go up as long as possible
//
//        if let completePath,
//           var completePathUrl = URL(string: completePath) {
//            completePathUrl.deleteLastPathComponent()
//            let stackEntry = ArchiveItemStackEntry(
//                type: .Directory,
//                localPath: completePathUrl,
//                archivePath: nil,
//                tempId: nil,
//                archiveType: nil)
//            loadStackEntry(stackEntry, push: false)
//        }
//    }
    
    /// Loads the archive from the given url
    /// - Parameter url: archive url
    func load(_ url: URL) throws {
        // load the content depending of the type
        do {
            // Check if this is a dir first. This will throw in case
            // the path does not exist
            let isDirectory = try isDirectory(path: url)
            
            if isDirectory {
                // directory
                let stackEntry = ArchiveItemStackEntry(
                    type: .Directory,
                    name: url.lastPathComponent,
                    localPath: url,
                    archivePath: nil,
                    tempId: nil,
                    archiveType: nil)
                loadStackEntry(stackEntry, clear: true)
            } else {
                let stackEntry = ArchiveItemStackEntry(
                    type: .Archive,
                    name: url.lastPathComponent,
                    localPath: url,
                    archivePath: "",
                    tempId: nil,
                    archiveType: ext)
                loadStackEntry(stackEntry, clear: true)
            }
        } catch let error as CocoaError {
            switch error.code {
            case .fileReadNoPermission, .fileReadUnknown:
                print("no access")
                errorMessage = "MacPacker does not have access to the parent directory."
            case .fileNoSuchFile:
                print("file not found")
                errorMessage = "The given file does not seem to exist"
            default:
                print("unknown CocoaError")
                print(error)
            }
        } catch {
            print(error)
        }
    }
    
    /// Opens the given item. This can be one of the following cases:
    /// - File in directory > open the file with system default action
    /// - Directory > show the content of the directory
    /// - Archive > show the content of the archive depending on the archive type
    /// - File in archive > extract just this file if possible, then open it with system default
    /// - Directory in archive > go one level down in archive if this is supported, otherwise, extract and then go to directory
    /// - Parameter item: The item to open
    func open(_ item: ArchiveItem) throws -> Archive2OpenResult {
        // if the selected item is the parent item (the one with ..),
        // then just go back in the stack
        if item == ArchiveItem.parent {
            // Problem when going up on parent on first stack level.
            stack.pop()
            if let parent = stack.peek() {
                loadStackEntry(parent, push: false)
            } else {
                // we're at the top of the archive, the next level
                // is a directory for sure
                // so let's check access first
//                try moveDirectoryUp(item)
                return .leaveDirectory
            }
            
            return .success
        }
        
        // The item selected is not the parent. So check if this is a file,
        // and if yes, whether it is a supported archive.
        if item.type == .file {
            if isSupportedArchive(ext: item.ext) {
                // file, and supported archive, open as a new stack entry
                
                // two possibilities
                // 1. the archive selected is extracted already > just open it,
                //    but set tempId, not archive path
                // 2. it is not extracted, so it was shown in the file list based
                //    on the virtual archive contetn > extract first, then create
                //    stackentry
                if let currentStackEntry = stack.peek() {
                    if currentStackEntry.type == .Archive && currentStackEntry.archivePath == nil {
                        // the previous stack entry is an archive, and the archive path is nil which
                        // means that it physically exists on the local drive
                        
                        // distinguish between a real local drive vs a temp drive
                        if currentStackEntry.tempId == nil {
                            print("Error: this should not happen")
                        } else {
                            if let path = item.path {
                                let stackEntry = ArchiveItemStackEntry(
                                    type: .Archive,
                                    name: item.name,
                                    localPath: path,
                                    archivePath: "",
                                    tempId: nil,
                                    archiveType: item.ext)
                                loadStackEntry(stackEntry)
                            }
                        }
                    } else if (currentStackEntry.type == .Archive || currentStackEntry.type == .ArchiveDirectory) && currentStackEntry.archivePath != nil {
                        // the previous stack entry is an archive, but there is no
                        // temp id, so it was not extracted yet
                        // > extract first
                        if let archiveType = currentStackEntry.archiveType,
                           let handler = ArchiveHandler.for(ext: archiveType),
                           let tempDir = handler.extractFileToTemp(
                                path: currentStackEntry.localPath,
                                item: item) {
//                           let tempDir = try? ArchiveType
//                            .with(archiveType)
//                            .extractFileToTemp(
//                                path: currentStackEntry.localPath,
//                                item: item) {
                            
                            // now, create the new stack entry
                            let stackEntry = ArchiveItemStackEntry(
                                type: .Archive,
                                name: item.name,
                                localPath: tempDir,
                                archivePath: "",
                                tempId: nil,
                                archiveType: item.ext)
                            loadStackEntry(stackEntry)
                            
                            // adds the newly created temp dir to the list of temp dirs. This
                            // is required to clean them up later.
                            if tempDir.isDirectory {
                                tempDirs.append(tempDir)
                            } else {
                                var td = tempDir
                                td.deleteLastPathComponent()
                                tempDirs.append(td)
                            }
                        }
                    } else if currentStackEntry.type == .Directory {
                        // just open the file in this case using the system methods
                    }
                }
            } else {
                if let currentStackEntry = stack.peek(),
                   let archiveType = currentStackEntry.archiveType,
                   let handler = ArchiveHandler.for(ext: archiveType),
                   let tempUrl = handler.extractFileToTemp(
//                   let tempUrl = try? ArchiveType
//                    .with(archiveType)
//                    .extractFileToTemp(
                        path: currentStackEntry.localPath,
                        item: item) {
                    
                    NSWorkspace.shared.open(tempUrl)
                }
            }
        } else if item.type == .directory {
            if item.virtualPath == nil {
                let stackEntry = ArchiveItemStackEntry(
                    type: .Directory,
                    name: item.name,
                    localPath: item.path!,
                    archivePath: nil,
                    tempId: nil,
                    archiveType: nil)
                loadStackEntry(stackEntry, push: false)
            } else if let currentStackEntry = stack.peek(),
                      let archivePath = currentStackEntry.archivePath {
                let stackEntry = ArchiveItemStackEntry(
                    type: .ArchiveDirectory, //Directory,
                    name: item.name,
                    localPath: currentStackEntry.localPath,
                    archivePath: archivePath == "" ? item.name : archivePath + "/" + item.name,
                    tempId: currentStackEntry.tempId,
                    archiveType: currentStackEntry.archiveType)
                loadStackEntry(stackEntry)
            } else {
                print("else")
            }
        }
        
        return .success
    }
    
    /// Extracts the given item to a temporary location. This is usually used to peek into that item
    /// - Parameter item: The item to extract
    /// - Returns: The URL to which the item was extracted. This is a temporary URL
    public func extractFileToTemp(_ item: ArchiveItem) -> URL? {
        if let currentStackEntry = stack.peek(),
           let archiveType = currentStackEntry.archiveType,
           let handler = ArchiveHandler.for(ext: archiveType),
           let tempUrl = handler.extractFileToTemp(
//           let tempUrl = try? ArchiveType
//            .with(archiveType)
//            .extractFileToTemp(
                path: currentStackEntry.localPath,
                item: item) {
            
            return tempUrl
        }
        return nil
    }
    
    /// Loads the content of the given directory. This is especially used
    /// when navigating outside of archives
    /// - Parameter url: url to load
    private func loadDirectoryContent(url: URL) throws {
        let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])
        var resultDirectories: [ArchiveItem] = []
        var resultFiles: [ArchiveItem] = []
        
        // add the possibility to go up
        resultDirectories.append(ArchiveItem.parent)
        
        // now add all items in the dir
        for url in contents {
            var isDirectory = false
            var fileSize: Int = -1
            do {
                let resourceValue = try url.resourceValues(forKeys: [.isDirectoryKey, .totalFileSizeKey])
                isDirectory = resourceValue.isDirectory ?? false
                fileSize = resourceValue.totalFileSize ?? -1
            } catch {

            }
            
            var fileItemType: ArchiveItemType = isDirectory ? .directory : .file
            if fileItemType == .file && isSupportedArchive(ext: url.pathExtension) {
                fileItemType = .archive
            }
            let fileItem = ArchiveItem(path: url, type: fileItemType, size: fileSize)
            
            if fileItemType == .directory {
                resultDirectories.append(fileItem)
            } else {
                resultFiles.append(fileItem)
            }
        }
        items = resultDirectories.sorted {
            return $0.name < $1.name
        }
        items.append(contentsOf: resultFiles.sorted {
            return $0.name < $1.name
        })
        print("items loaded \(items.count)")
    }
}
