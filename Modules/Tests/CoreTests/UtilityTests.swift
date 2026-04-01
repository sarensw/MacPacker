import Testing
import Foundation
@testable import Core

extension AllCoreTests {

    // MARK: - 1. ArchiveCapabilities

    @MainActor struct ArchiveCapabilitiesTests {

        @Test func fromStringListContents() {
            let cap = ArchiveCapabilities.from(string: "listContents")
            #expect(cap == .listContents)
        }

        @Test func fromStringExtractFiles() {
            let cap = ArchiveCapabilities.from(string: "extractFiles")
            #expect(cap == .extractFiles)
        }

        @Test func fromStringCreate() {
            let cap = ArchiveCapabilities.from(string: "create")
            #expect(cap == .create)
        }

        @Test func fromStringDelete() {
            let cap = ArchiveCapabilities.from(string: "delete")
            #expect(cap == .delete)
        }

        @Test func fromStringAdd() {
            let cap = ArchiveCapabilities.from(string: "add")
            #expect(cap == .add)
        }

        @Test func fromStringRewriteInPlace() {
            let cap = ArchiveCapabilities.from(string: "rewriteInPlace")
            #expect(cap == .rewriteInPlace)
        }

        @Test func fromStringInvalidReturnsNil() {
            let cap = ArchiveCapabilities.from(string: "nonexistent")
            #expect(cap == nil)
        }

        @Test func fromStringsMultipleValid() {
            let caps = ArchiveCapabilities.from(strings: ["listContents", "extractFiles", "create"])
            #expect(caps.contains(.listContents))
            #expect(caps.contains(.extractFiles))
            #expect(caps.contains(.create))
            #expect(!caps.contains(.delete))
        }

        @Test func fromStringsIgnoresInvalid() {
            let caps = ArchiveCapabilities.from(strings: ["listContents", "bogus", "delete"])
            #expect(caps.contains(.listContents))
            #expect(caps.contains(.delete))
            #expect(!caps.contains(.extractFiles))
        }

        @Test func fromStringsEmptyArrayReturnsEmpty() {
            let caps = ArchiveCapabilities.from(strings: [])
            #expect(caps.isEmpty)
        }
    }

    // MARK: - 2. ArchivePasswordRequest

    @MainActor struct ArchivePasswordRequestTests {

        @Test func defaultValues() {
            let url = URL(fileURLWithPath: "/tmp/test.zip")
            let req = ArchivePasswordRequest(url: url)
            #expect(req.url == url)
            #expect(req.attempt == 1)
            #expect(req.message == nil)
        }

        @Test func customValues() {
            let url = URL(fileURLWithPath: "/tmp/test.rar")
            let req = ArchivePasswordRequest(url: url, attempt: 3, message: "Wrong password")
            #expect(req.url == url)
            #expect(req.attempt == 3)
            #expect(req.message == "Wrong password")
        }
    }

    // MARK: - 3. ArchiveEngineType

    @MainActor struct ArchiveEngineTypeTests {

        @Test func configIdInitXad() {
            let t = ArchiveEngineType(configId: "xad")
            #expect(t == .xad)
        }

        @Test func configIdInit7zip() {
            let t = ArchiveEngineType(configId: "7zip")
            #expect(t == .`7zip`)
        }

        @Test func configIdInitSwc() {
            let t = ArchiveEngineType(configId: "swc")
            #expect(t == .swc)
        }

        @Test func configIdInitUnknownReturnsNil() {
            let t = ArchiveEngineType(configId: "unknown")
            #expect(t == nil)
        }

        @Test func configIdInitCaseInsensitive() {
            let t = ArchiveEngineType(configId: "XAD")
            #expect(t == .xad)
        }

        @Test func configIdPropertyXad() {
            #expect(ArchiveEngineType.xad.configId == "xad")
        }

        @Test func configIdProperty7zip() {
            #expect(ArchiveEngineType.`7zip`.configId == "7zip")
        }

        @Test func configIdPropertySwc() {
            #expect(ArchiveEngineType.swc.configId == "swc")
        }
    }

    // MARK: - 4. ArchiveItem

    @MainActor struct ArchiveItemTests {

        @Test func fileItemExtIsSet() {
            let item = ArchiveItem(name: "photo.jpg", type: .file)
            #expect(item.ext == "jpg")
            #expect(item.children == nil)
        }

        @Test func directoryItemExtIsEmptyAndChildrenIsEmptyArray() {
            let item = ArchiveItem(name: "myFolder", type: .directory)
            #expect(item.ext == "")
            #expect(item.children != nil)
            #expect(item.children?.isEmpty == true)
        }

        @Test func rootItemChildrenIsNil() {
            let item = ArchiveItem(name: "root", type: .root)
            #expect(item.children == nil)
        }

        @Test func defaultSizesAreMinusOne() {
            let item = ArchiveItem(name: "file.txt", type: .file)
            #expect(item.compressedSize == -1)
            #expect(item.uncompressedSize == -1)
        }

        @Test func nameWithNoDotExtIsEmpty() {
            let item = ArchiveItem(name: "Makefile", type: .file)
            #expect(item.ext == "")
        }

        @Test func nameStartingWithDotExtIsEmpty() {
            let item = ArchiveItem(name: ".gitignore", type: .file)
            #expect(item.ext == "")
        }

        @Test func nameWithMultipleDotsExtIsLastPart() {
            let item = ArchiveItem(name: "archive.tar.gz", type: .file)
            #expect(item.ext == "gz")
        }

        @Test func addChildToFile() {
            let parent = ArchiveItem(name: "file.txt", type: .file)
            #expect(parent.children == nil)

            let child = ArchiveItem(name: "child.txt", type: .file)
            parent.addChild(child.id)

            #expect(parent.children != nil)
            #expect(parent.children?.count == 1)
            #expect(parent.children?.first == child.id)
        }

        @Test func addMultipleChildren() {
            let parent = ArchiveItem(name: "folder", type: .directory)
            let child1 = ArchiveItem(name: "a.txt", type: .file)
            let child2 = ArchiveItem(name: "b.txt", type: .file)

            parent.addChild(child1.id)
            parent.addChild(child2.id)

            #expect(parent.children?.count == 2)
            #expect(parent.children?.contains(child1.id) == true)
            #expect(parent.children?.contains(child2.id) == true)
        }

        @Test func setUrlAndTypeId() {
            let item = ArchiveItem(name: "nested.zip", type: .archive)
            let url = URL(fileURLWithPath: "/tmp/nested.zip")
            item.set(url: url, typeId: "zip")
            #expect(item.url == url)
            #expect(item.archiveTypeId == "zip")
        }

        @Test func setName() {
            let item = ArchiveItem(name: "old.txt", type: .file)
            item.set(name: "new.txt")
            #expect(item.name == "new.txt")
        }

        @Test func sameItemEqualsItself() {
            let item = ArchiveItem(name: "test.txt", type: .file)
            #expect(item == item)
        }

        @Test func hashConsistency() {
            let item = ArchiveItem(name: "test.txt", type: .file)
            var hasher1 = Hasher()
            item.hash(into: &hasher1)
            let hash1 = hasher1.finalize()

            var hasher2 = Hasher()
            item.hash(into: &hasher2)
            let hash2 = hasher2.finalize()

            #expect(hash1 == hash2)
        }
    }

    // MARK: - 5. ArchiveHierarchyPrinter

    @MainActor struct ArchiveHierarchyPrinterTests {

        @Test func printHierarchyWithEntriesDoesNotCrash() {
            let printer = ArchiveHierarchyPrinter()
            let root = ArchiveItem(name: "root", type: .root)
            let child = ArchiveItem(name: "child.txt", type: .file, parent: root.id)
            root.addChild(child.id)

            var entries: [UUID: ArchiveItem] = [:]
            entries[root.id] = root
            entries[child.id] = child

            // Should not crash; output goes to stdout
            printer.printHierarchy(entries: entries, id: root.id)
        }

        @Test func printHierarchyEmptyEntries() {
            let printer = ArchiveHierarchyPrinter()
            let fakeId = UUID()
            // Missing id in empty dict - should do nothing, not crash
            printer.printHierarchy(entries: [:], id: fakeId)
        }

        @Test func printHierarchyMissingId() {
            let printer = ArchiveHierarchyPrinter()
            let root = ArchiveItem(name: "root", type: .root)
            var entries: [UUID: ArchiveItem] = [:]
            entries[root.id] = root

            let missingId = UUID()
            // id not in dict - guard returns early
            printer.printHierarchy(entries: entries, id: missingId)
        }
    }

    // MARK: - 6. CacheCleaner

    @MainActor struct CacheCleanerTests {

        @Test func cleanRemovesTempDirectory() throws {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            #expect(FileManager.default.fileExists(atPath: tempDir.path))

            let cleaner = CacheCleaner()
            cleaner.clean(tempDirectories: [tempDir])

            #expect(!FileManager.default.fileExists(atPath: tempDir.path))
        }

        @Test func cleanEmptyArrayDoesNotCrash() {
            let cleaner = CacheCleaner()
            cleaner.clean(tempDirectories: [])
        }
    }

    // MARK: - 7. ArchiveSupportUtilities

    @MainActor struct ArchiveSupportUtilitiesTests {

        @Test func createTempDirectoryReturnsValidUrl() throws {
            let utils = ArchiveSupportUtilities()
            let result = utils.createTempDirectory()
            #expect(result != nil)
            #expect(FileManager.default.fileExists(atPath: result!.url.path))

            // Cleanup
            try? FileManager.default.removeItem(at: result!.url)
        }

        @Test func findHandlerAndUrlWithTypeIdAndUrl() {
            let utils = ArchiveSupportUtilities()
            let item = ArchiveItem(name: "file.txt", type: .file)
            let url = URL(fileURLWithPath: "/tmp/archive.zip")
            item.set(url: url, typeId: "zip")

            var entries: [UUID: ArchiveItem] = [:]
            entries[item.id] = item

            let result = utils.findHandlerAndUrl(for: item, in: entries)
            #expect(result != nil)
            #expect(result?.0 == "zip")
            #expect(result?.1 == url)
        }

        @Test func findHandlerAndUrlViaParentChain() {
            let utils = ArchiveSupportUtilities()

            let root = ArchiveItem(name: "root", type: .root)
            let url = URL(fileURLWithPath: "/tmp/archive.zip")
            root.set(url: url, typeId: "zip")

            let child = ArchiveItem(name: "nested.txt", type: .file, parent: root.id)
            root.addChild(child.id)

            var entries: [UUID: ArchiveItem] = [:]
            entries[root.id] = root
            entries[child.id] = child

            let result = utils.findHandlerAndUrl(for: child, in: entries)
            #expect(result != nil)
            #expect(result?.0 == "zip")
            #expect(result?.1 == url)
        }

        @Test func findHandlerAndUrlNoParentNoTypeIdReturnsNil() {
            let utils = ArchiveSupportUtilities()
            let item = ArchiveItem(name: "orphan.txt", type: .file)

            var entries: [UUID: ArchiveItem] = [:]
            entries[item.id] = item

            let result = utils.findHandlerAndUrl(for: item, in: entries)
            #expect(result == nil)
        }

        @Test func findHandlerAndUrlCycleDetection() {
            let utils = ArchiveSupportUtilities()
            let item = ArchiveItem(name: "loop.txt", type: .file, parent: nil)
            // Point parent to itself to create a cycle
            item.parent = item.id

            var entries: [UUID: ArchiveItem] = [:]
            entries[item.id] = item

            // Should not infinite-loop; cycle detection breaks out
            let result = utils.findHandlerAndUrl(for: item, in: entries)
            #expect(result == nil)
        }
    }

    // MARK: - 8. ArchiveTypeCatalog

    @MainActor struct ArchiveTypeCatalogTests {

        @Test func getAllTypesReturnsNonEmpty() {
            let catalog = ArchiveTypeCatalog()
            let types = catalog.getAllTypes()
            #expect(!types.isEmpty)
        }

        @Test func getTypeForZipReturnsZip() {
            let catalog = ArchiveTypeCatalog()
            let type = catalog.getType(for: "zip")
            #expect(type != nil)
            #expect(type?.id == "zip")
        }

        @Test func getTypeForNonexistentReturnsNil() {
            let catalog = ArchiveTypeCatalog()
            let type = catalog.getType(for: "nonexistent")
            #expect(type == nil)
        }

        @Test func getTypeWhereMatchingPredicate() {
            let catalog = ArchiveTypeCatalog()
            let type = catalog.getType(where: { $0.id == "zip" })
            #expect(type != nil)
            #expect(type?.id == "zip")
        }

        @Test func allCompositionsReturnsNonEmpty() {
            let catalog = ArchiveTypeCatalog()
            let compositions = catalog.allCompositions()
            #expect(!compositions.isEmpty)
        }

        @Test func allFormatIdsReturnsNonEmpty() {
            let catalog = ArchiveTypeCatalog()
            let ids = catalog.allFormatIds()
            #expect(!ids.isEmpty)
        }

        @Test func engineOptionsForZipReturnsEngines() {
            let catalog = ArchiveTypeCatalog()
            let options = catalog.engineOptions(for: "zip")
            #expect(!options.isEmpty)
        }

        @Test func engineOptionsForNonexistentReturnsEmpty() {
            let catalog = ArchiveTypeCatalog()
            let options = catalog.engineOptions(for: "nonexistent")
            #expect(options.isEmpty)
        }

        @Test func defaultEngineForZipReturnsEngine() {
            let catalog = ArchiveTypeCatalog()
            let engine = catalog.defaultEngine(for: "zip")
            #expect(engine != nil)
        }

        @Test func defaultEngineForNonexistentReturnsNil() {
            let catalog = ArchiveTypeCatalog()
            let engine = catalog.defaultEngine(for: "nonexistent")
            #expect(engine == nil)
        }
    }

    // MARK: - 9. ArchiveTypeDetector

    @MainActor struct ArchiveTypeDetectorTests {

        @Test func detectForZipFileReturnsZip() {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            let result = detector.detect(for: url)
            #expect(result != nil)
            #expect(result?.type.id == "zip")
        }

        @Test func detectForUnknownExtensionUsessMagicOrNil() {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)
            let url = URL(fileURLWithPath: "/tmp/fakefile.xyznotreal")

            let result = detector.detect(for: url)
            // Unknown extension with no file to read magic from -> nil
            #expect(result == nil)
        }

        @Test func detectByExtensionSimple() {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)
            let url = URL(fileURLWithPath: "/tmp/test.zip")

            let result = detector.detectByExtension(for: url, considerComposition: true)
            #expect(result != nil)
            #expect(result?.type.id == "zip")
        }

        @Test func detectByExtensionCompoundTarGz() {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)
            let url = URL(fileURLWithPath: "/tmp/archive.tar.gz")

            let result = detector.detectByExtension(for: url, considerComposition: true)
            #expect(result != nil)
            #expect(result?.composition != nil)
            #expect(result?.type.id == "tar")
        }

        @Test func detectByExtensionNoCompositionTarGzDetectsGz() {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)
            let url = URL(fileURLWithPath: "/tmp/archive.tar.gz")

            let result = detector.detectByExtension(for: url, considerComposition: false)
            #expect(result != nil)
            #expect(result?.composition == nil)
            // Without composition, it should detect by the bare extension "gz"
            #expect(result?.type.extensions.contains("gz") == true)
        }

        @Test func detectByExtZipReturnsZip() {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)

            let result = detector.detectBy(ext: "zip")
            #expect(result != nil)
            #expect(result?.type.id == "zip")
        }

        @Test func detectByExtUnknownReturnsNil() {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)

            let result = detector.detectBy(ext: "unknown")
            #expect(result == nil)
        }

        @Test func getNameWithoutExtensionSimple() {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)
            let url = URL(fileURLWithPath: "/tmp/archive.zip")

            let name = detector.getNameWithoutExtension(for: url)
            #expect(name == "archive")
        }

        @Test func getNameWithoutExtensionCompound() {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)
            let url = URL(fileURLWithPath: "/tmp/archive.tar.gz")

            let name = detector.getNameWithoutExtension(for: url)
            #expect(name == "archive")
        }

        @Test func detectByMagicNumberWithTestArchive() {
            let catalog = ArchiveTypeCatalog()
            let detector = ArchiveTypeDetector(catalog: catalog)
            let folderURL = Bundle.module.url(forResource: "defaultArchives", withExtension: nil)!
            let url = folderURL.appendingPathComponent("defaultArchive.zip")

            let result = detector.detectByMagicNumber(for: url)
            #expect(result != nil)
            #expect(result?.type.id == "zip")
            #expect(result?.source == .magic)
        }
    }

    // MARK: - 10. ArchiveEngineConfigStore

    @MainActor struct ArchiveEngineConfigStoreTests {

        @Test func initCreatesStore() {
            let catalog = ArchiveTypeCatalog()
            let store = ArchiveEngineConfigStore(catalog: catalog)
            #expect(store != nil)
        }

        @Test func selectedEngineDefaultsFromCatalog() {
            let catalog = ArchiveTypeCatalog()
            let store = ArchiveEngineConfigStore(catalog: catalog)
            let engine = store.selectedEngine(for: "zip")
            // Should come from catalog default
            #expect(engine != nil)
        }

        @Test func setSelectedEngineStoresOverride() {
            let catalog = ArchiveTypeCatalog()
            let store = ArchiveEngineConfigStore(catalog: catalog)

            // Find a valid engine for zip from the catalog options
            let options = catalog.engineOptions(for: "zip")
            guard let firstOption = options.first,
                  let engineType = ArchiveEngineType(configId: firstOption.id) else {
                return
            }

            store.setSelectedEngine(engineType, for: "zip")
            let selected = store.selectedEngine(for: "zip")
            #expect(selected == engineType)
        }

        @Test func setSelectedEngineRejectsUnknownEngine() {
            let catalog = ArchiveTypeCatalog()
            let store = ArchiveEngineConfigStore(catalog: catalog)
            let original = store.selectedEngine(for: "zip")

            // swc is likely not a valid engine for zip, so it should be rejected
            store.setSelectedEngine(.swc, for: "zip")
            let afterAttempt = store.selectedEngine(for: "zip")
            // If swc is not in the zip options, the override should not have been set
            let validIds = catalog.engineOptions(for: "zip").map(\.id)
            if !validIds.contains("swc") {
                #expect(afterAttempt == original)
            }
        }
    }

    // MARK: - 11. ArchiveEngineSelector

    @MainActor struct ArchiveEngineSelectorTests {

        @Test func initCreatesSelector() {
            let catalog = ArchiveTypeCatalog()
            let store = ArchiveEngineConfigStore(catalog: catalog)
            let selector = ArchiveEngineSelector(catalog: catalog, configStore: store)
            #expect(selector != nil)
        }

        @Test func engineForZipReturnsEngine() {
            let catalog = ArchiveTypeCatalog()
            let store = ArchiveEngineConfigStore(catalog: catalog)
            let selector = ArchiveEngineSelector(catalog: catalog, configStore: store)
            let engine = selector.engine(for: "zip")
            #expect(engine != nil)
        }

        @Test func engineForNonexistentReturnsNil() {
            let catalog = ArchiveTypeCatalog()
            let store = ArchiveEngineConfigStore(catalog: catalog)
            let selector = ArchiveEngineSelector(catalog: catalog, configStore: store)
            let engine = selector.engine(for: "nonexistent")
            #expect(engine == nil)
        }

        @Test func engineForType7zipReturnsArchive7ZipEngine() {
            let catalog = ArchiveTypeCatalog()
            let store = ArchiveEngineConfigStore(catalog: catalog)
            let selector = ArchiveEngineSelector(catalog: catalog, configStore: store)
            let engine = selector.engine(for: .`7zip`)
            #expect(engine is Archive7ZipEngine)
        }

        @Test func engineTypeForZipReturnsEngineType() {
            let catalog = ArchiveTypeCatalog()
            let store = ArchiveEngineConfigStore(catalog: catalog)
            let selector = ArchiveEngineSelector(catalog: catalog, configStore: store)
            let engineType = selector.engineType(for: "zip")
            #expect(engineType != nil)
        }
    }

    // MARK: - 12. Logger

    @MainActor struct LoggerTests {

        @Test func logDoesNotCrash() {
            Logger.log("test message")
        }

        @Test func debugDoesNotCrash() {
            Logger.debug("debug message")
        }

        @Test func infoDoesNotCrash() {
            Logger.info("info message")
        }

        @Test func warningDoesNotCrash() {
            Logger.warning("warning message")
        }

        @Test func errorStringDoesNotCrash() {
            Logger.error("error message")
        }

        @Test func errorErrorDoesNotCrash() {
            struct TestError: Error {}
            Logger.error(TestError())
        }

        @Test func startDoesNotCrash() {
            Logger.start()
        }

        @Test func logLevelTailBeatLevel() {
            #expect(LogLevel.Trace.tailBeatLevel == .Trace)
            #expect(LogLevel.Debug.tailBeatLevel == .Debug)
            #expect(LogLevel.Info.tailBeatLevel == .Info)
            #expect(LogLevel.Warning.tailBeatLevel == .Warning)
            #expect(LogLevel.Error.tailBeatLevel == .Error)
            #expect(LogLevel.Fatal.tailBeatLevel == .Fatal)
        }
    }

    // MARK: - 13. Bool+Extensions

    @MainActor struct BoolExtensionsTests {

        @Test func macOS13ReturnsBool() {
            let value = Bool.macOS13
            // On macOS 14+ this should be false
            #expect(value == false)
        }
    }

    // MARK: - 14. ArchiveBatchResolver

    @MainActor struct ArchiveBatchResolverTests {

        @Test func resolveBatchesExpandsDirectoryChildren() throws {
            let resolver = ArchiveBatchResolver()

            // Build a small hierarchy: root -> dir -> [file1, file2]
            let root = ArchiveItem(name: "root", type: .root)
            let rootUrl = URL(fileURLWithPath: "/tmp/archive.zip")
            root.set(url: rootUrl, typeId: "zip")

            let dir = ArchiveItem(name: "folder", type: .directory, parent: root.id)
            root.addChild(dir.id)

            let file1 = ArchiveItem(index: 0, name: "a.txt", type: .file, parent: dir.id)
            let file2 = ArchiveItem(index: 1, name: "b.txt", type: .file, parent: dir.id)
            dir.addChild(file1.id)
            dir.addChild(file2.id)

            var entries: [UUID: ArchiveItem] = [:]
            entries[root.id] = root
            entries[dir.id] = dir
            entries[file1.id] = file1
            entries[file2.id] = file2

            let selector = ArchiveEngineSelector7zip()

            let batches = try resolver.resolveBatches(for: [dir], in: entries, using: selector)
            #expect(!batches.isEmpty)

            // The batch should contain the directory and its two children
            let allItems = batches.flatMap(\.items)
            #expect(allItems.count == 3)
            let allIds = Set(allItems.map(\.id))
            #expect(allIds.contains(dir.id))
            #expect(allIds.contains(file1.id))
            #expect(allIds.contains(file2.id))
        }
    }
}
