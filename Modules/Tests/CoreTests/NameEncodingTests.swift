//
//  NameEncodingTests.swift
//  Modules
//
//  An archive that does not say what its names are written in shows them as
//  they were meant, and extracts them under those names (#373).
//

import Foundation
import Swift7zip
import Testing
@testable import Core

/// The engines that read these formats; 7-Zip is the default for all of them.
private let engines: [any ArchiveEngineSelectorProtocol] = [ArchiveEngineSelector7zip(), ArchiveEngineSelectorXad()]

/// Settings, which can name another engine while a window stays open.
private final class ChangingSelector: ArchiveEngineSelectorProtocol, @unchecked Sendable {
    var configured = ArchiveEngineType.`7zip`

    func engine(for id: String) -> ArchiveEngine? { engine(for: configured) }

    func engine(for type: ArchiveEngineType) -> ArchiveEngine {
        switch type {
        case .`7zip`: Archive7ZipEngine()
        case .xad: ArchiveXadEngine()
        case .swc: ArchiveSwcEngine()
        }
    }

    func engineType(for id: String) -> ArchiveEngineType? { configured }
}

/// `gbk_sidecar.zip` on disk: the sidecar folded, the decoy still there.
private let sidecarFiles = ["中文目录", "中文目录/._说明.txt", "中文目录/你好世界.txt", "中文目录/说明.txt"].sorted()

private let cp866Tree = ["Документы", "Документы/Отчёт.txt", "Новая папка", "Новая папка/Договор.txt"].sorted()

/// A fixture from `TestArchives/encodings` and the tree it holds.
private struct Fixture: Sendable, CustomTestStringConvertible {
    let file: String
    let tree: [String]
    var testDescription: String { file }
}

/// `データ\\表示.txt` and so on, all four with a 0x5C inside a character.
private let sjisBackslashTree = ["データ", "データ/表示.txt", "ソフト.txt", "能力表.txt", "予定", "予定/申請書.txt"]

private let gbkTree = [
    "中文目录", "中文目录/你好世界.txt", "中文目录/说明文档.txt",
    "图片", "图片/风景.txt", "一些.txt", "readme.txt"]

private let fixtures = [
    Fixture(file: "gbk.zip", tree: gbkTree),
    Fixture(file: "big5.zip", tree: [
        "繁體中文", "繁體中文/許功蓋.txt", "說明.txt", "報告", "報告/年度預算.txt"]),
    Fixture(file: "shiftjis.zip", tree: [
        "表示", "表示/ソフト能力.txt", "日本語のファイル.txt", "データ", "データ/テスト.txt"]),
    Fixture(file: "cp949.zip", tree: [
        "문서", "문서/보고서.txt", "사진", "사진/풍경.txt", "설명서.txt"]),
    Fixture(file: "cp850.zip", tree: [
        "Müller", "Müller/Größe.txt", "Übersicht.txt", "résumé.txt", "São Paulo.txt", "Søren.txt"]),
    Fixture(file: "cp866.zip", tree: cp866Tree),
    Fixture(file: "gbk_mixed.zip", tree: [
        "中文目录", "中文目录/你好世界.txt", "新建文档.txt"]),
    Fixture(file: "gbk_flagged.zip", tree: [
        "中文目录", "中文目录/你好世界.txt", "Отчёт.txt", "Señor.txt", "Café.txt"]),
    Fixture(file: "gbk.tar", tree: [
        "中文目录", "中文目录/你好世界.txt", "图片", "图片/风景.txt", "一些.txt"]),
    Fixture(file: "gbk_combining.zip", tree: [
        "工作", "工作/通知", "工作/通知/会议.txt", "工作/通知/计划.txt", "工作/说明.txt",
        "中文目录", "中文目录/通知.txt", "中文目录/同学录.xls", "中文目录/你好世界.txt"]),
    Fixture(file: "gbk_escape_bytes.zip", tree: [
        "李静简历.doc", "杨静", "杨静/报告.txt", "李经理的报告.xlsx", "羁绊.txt", "说明.txt"]),
    Fixture(file: "big5_escape_bytes.zip", tree: ["溫度控制器手冊.pdf", "說明.txt"]),
    Fixture(file: "big5_windows.zip", tree: [
        "恒生銀行", "恒生銀行/年度報告.txt", "宏碁", "宏碁/說明.txt"]),
    Fixture(file: "gbk_unicode_path.zip", tree: [
        "中文目录", "中文目录/你好世界.txt", "新建文档.txt", "Señor.txt", "Отчёт.txt"]),
    Fixture(file: "gbk_cv.zip", tree: ["个人简历模板.doc"]),
    Fixture(file: "gbk_forms.zip", tree: ["简历模板.doc", "报名表.xls"]),
    Fixture(file: "cp866_symbols.zip", tree: [
        "Документы", "Документы/Отчёт.txt", "Приказ №15.doc", "Новая папка", "Новая папка/Договор.txt",
        "Письмо.txt", "Акт.doc", "Счёт.xls"]),
    Fixture(file: "cp850_symbols.zip", tree: ["Übersicht.txt", "§ 34 Änderung.pdf", "Müller.doc"]),
    Fixture(file: "sjis_backslash.lzh", tree: sjisBackslashTree),
    Fixture(file: "sjis_backslash.rar", tree: sjisBackslashTree),
    Fixture(file: "sjis_backslash.cab", tree: sjisBackslashTree),
]

/// What is left of the UTF-8 in `utf8_stray_latin1.tar`, whatever its stray reads as.
private let strayLatin1Tree = ["Müller", "Müller/Größe.txt", "Übersicht.txt", "Änderung.doc"].sorted()

private let macRomanTree = [
    "Bücher", "Bücher/Übersicht.txt", "Bücher/Größe.txt", "Prüfung.doc", "Résumé.doc", "Café.txt", "Señor.txt", "plain.txt"]

extension AllCoreTests {
    @MainActor struct NameEncodingTests {
        private func url(of file: String) throws -> URL {
            try #require(Bundle.module.url(forResource: "encodings", withExtension: nil))
                .appendingPathComponent(file).standardizedFileURL
        }

        private func open(
            _ file: String,
            with selector: any ArchiveEngineSelectorProtocol = ArchiveEngineSelector7zip()
        ) async throws -> ArchiveState {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: selector)
            state.open(url: try url(of: file))
            try await state.openTask?.value
            #expect(state.error == nil)
            return state
        }

        /// What the window shows: every row, by the names leading to it. A name
        /// read two ways shows up here as a folder twice.
        private func tree(of state: ArchiveState) -> [String] {
            func path(_ item: ArchiveItem) -> String {
                guard let parent = item.parent.flatMap({ state.entries[$0] }), parent.type != .root
                else { return item.name }
                return path(parent) + "/" + item.name
            }
            return state.entries.values.filter { $0.type != .root }.map(path).sorted()
        }

        /// Everything below `folder`. By `readdir`: Foundation's listings leave out
        /// a "._name" beside its "name", which is what a sidecar left behind is.
        private func files(in folder: URL, below prefix: String = "") throws -> [String] {
            let stream = try #require(opendir(folder.path))
            defer { closedir(stream) }
            var found: [String] = []
            while let entry = readdir(stream) {
                let name = withUnsafeBytes(of: entry.pointee.d_name) {
                    String(decoding: $0.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self)
                }
                guard name != ".", name != ".." else { continue }
                found.append(prefix + name)
                if Int32(entry.pointee.d_type) == DT_DIR {
                    found += try files(in: folder.appendingPathComponent(name), below: prefix + name + "/")
                }
            }
            return found.sorted()
        }

        private func extractAll(_ state: ArchiveState, to folder: URL) async {
            await withCheckedContinuation { continuation in
                state.onStatusChange = { status in
                    if status == .done { continuation.resume() }
                }
                state.extract(to: folder, smart: false)
            }
            state.onStatusChange = nil
        }

        /// Writes the archive and waits for it. Fails when no write starts: going
        /// on from there, a test would look at the archive as it was.
        private func save(_ state: ArchiveState, to destination: URL? = nil) async throws {
            let saving = try #require(state.save(to: destination))
            await saving.value
            #expect(state.saveError == nil)
        }

        private func temporaryFolder() throws -> URL {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("NameEncodingTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }

        // MARK: Listing

        @Test(arguments: engines, fixtures)
        fileprivate func listsTheNames(selector: any ArchiveEngineSelectorProtocol, fixture: Fixture) async throws {
            let state = try await open(fixture.file, with: selector)
            #expect(tree(of: state) == fixture.tree.sorted())
        }

        // MARK: Extraction

        @Test(arguments: engines, fixtures)
        fileprivate func extractsAllUnderTheNames(selector: any ArchiveEngineSelectorProtocol, fixture: Fixture) async throws {
            let state = try await open(fixture.file, with: selector)
            let folder = try temporaryFolder()
            defer { try? FileManager.default.removeItem(at: folder) }

            await extractAll(state, to: folder)

            #expect(try files(in: folder) == fixture.tree.sorted())
        }

        @Test(arguments: engines, fixtures)
        fileprivate func extractsOneEntryUnderItsName(selector: any ArchiveEngineSelectorProtocol, fixture: Fixture) async throws {
            let state = try await open(fixture.file, with: selector)
            let item = try #require(state.entries.values.first { $0.type == .file })

            let extracted = try await state.extractToTemp(item: item)
            defer { try? FileManager.default.removeItem(at: extracted) }

            #expect(extracted.lastPathComponent == item.name)
            #expect(fixture.tree.contains { $0.hasSuffix(item.name) })
            #expect(FileManager.default.fileExists(atPath: extracted.path))
        }

        /// A name read in a code page is as untrusted as any other. 7-Zip's side
        /// drops the way up, XADMaster's makes it a folder named `__Parent__`.
        @Test(arguments: engines)
        fileprivate func aReadNameStaysInTheDestination(selector: any ArchiveEngineSelectorProtocol) async throws {
            let state = try await open("gbk_traversal.zip", with: selector)
            let folder = try temporaryFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let destination = folder.appendingPathComponent("a/b")
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

            await extractAll(state, to: destination)

            let landed = try files(in: folder).filter { $0 != "a" && $0 != "a/b" }
            #expect(landed.allSatisfy { $0.hasPrefix("a/b/") })
            #expect(landed.contains { $0.hasSuffix("/中文.txt") })
        }

        /// It lands in the destination, so that is where the list has it. As a
        /// folder its `..` is a name with a dot in front, which is hidden, and the
        /// archive looked empty with an item count above zero.
        @Test func aNameThatClimbsOutIsListedWhereItLands() async throws {
            let state = try await open("gbk_traversal.zip")

            #expect(state.childItems?.map(\.name) == ["中文.txt"])
            #expect(tree(of: state) == ["中文.txt"])

            let item = try #require(state.childItems?.first)
            let extracted = try await state.extractToTemp(item: item)
            defer { try? FileManager.default.removeItem(at: extracted) }
            #expect(FileManager.default.fileExists(atPath: extracted.path))
        }

        /// No flag vouches for `新建文档.txt`, and it decodes as GBK as well. Only
        /// its bytes can tell it is UTF-8, as it takes three per character.
        /// XADMaster reads a whole archive in one encoding, so 7-Zip only.
        @Test func aRealUTF8NameWithoutAFlagStaysUTF8() async throws {
            let state = try await open("gbk_unflagged.zip")
            #expect(tree(of: state) == ["中文目录", "中文目录/你好世界.txt", "新建文档.txt"].sorted())
        }

        /// A tar's pax record declares the name, as the flag does in a zip.
        /// XADMaster reads a whole archive in one encoding, so 7-Zip only.
        @Test func aPaxNameStaysWhatItSays() async throws {
            let state = try await open("gbk_pax.tar")
            #expect(tree(of: state) == [
                "中文目录", "中文目录/你好世界.txt", "新建文档.txt", "Señor.txt", "Отчёт.txt"].sorted())
        }

        /// The flag is on, as on anything a UTF-8 locale wrote, but the bytes are
        /// GBK: the flag says nothing then, and the archive gets a menu.
        @Test func aFlagOnBytesThatAreNotUTF8SaysNothing() async throws {
            let state = try await open("gbk_flag_wrong.zip")
            #expect(state.nameEncoding == .gb18030)
            #expect(tree(of: state) == ["中文目录", "中文目录/你好世界.txt"])
        }

        /// One name in Latin-1 among UTF-8 does not make the rest GBK that only
        /// looks like UTF-8, on disk least of all.
        @Test func oneStrayNameLeavesTheRestOfTheUTF8() async throws {
            let state = try await open("utf8_stray_latin1.tar")
            #expect(Set(strayLatin1Tree).isSubset(of: tree(of: state)))

            let folder = try temporaryFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            await extractAll(state, to: folder)
            #expect(Set(strayLatin1Tree).isSubset(of: try files(in: folder)))
        }

        /// `sub/../` is `sub`, as far as it is anywhere. Shown as a folder named
        /// `..` it is a hidden row with all of `sub` inside.
        @Test func aFolderEntryOfDotsIsNoFolder() async throws {
            let state = try await open("dotdot_entry.zip")
            #expect(state.childItems?.map(\.name) == ["sub"])
            #expect(tree(of: state) == ["sub", "sub/x.txt", "sub/y.txt"])

            let folder = try temporaryFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            await extractAll(state, to: folder)
            #expect(try files(in: folder) == ["sub", "sub/x.txt", "sub/y.txt"])
        }

        /// Each level detects on its own: the GBK inside a zip in CP1251 reads,
        /// though nothing reads the zip around it.
        @Test func anArchiveInsideReadsItsOwnNames() async throws {
            let state = try await open("nested_gbk.zip")
            let inner = try #require(state.entries.values.first { $0.name == "inner.zip" })

            try await state.openAsync(item: inner)

            #expect(tree(of: state).filter { $0.hasPrefix("inner.zip/") } == [
                "inner.zip/中文目录", "inner.zip/中文目录/你好世界.txt", "inner.zip/图片", "inner.zip/图片/风景.txt"])
        }

        // MARK: Mac archives

        /// The bytes of these names are letters in CP850 too, and 0x8E there is
        /// `Ä`. Only the format says they are Mac Roman.
        @Test func aStuffItArchiveIsInMacRoman() async throws {
            let state = try await open("macroman.sit", with: ArchiveEngineSelectorXad())
            #expect(state.nameEncoding == .macRoman)
            #expect(tree(of: state) == macRomanTree.sorted())

            let folder = try temporaryFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            await extractAll(state, to: folder)
            #expect(try files(in: folder) == macRomanTree.sorted())
        }

        @Test func aJapaneseStuffItArchiveIsNotInMacRoman() async throws {
            let state = try await open("macjapanese.sit", with: ArchiveEngineSelectorXad())
            #expect(state.nameEncoding == .shiftJIS)
            #expect(tree(of: state) == ["データ", "データ/日本語のファイル.txt", "説明書.txt", "写真.txt"].sorted())
        }

        /// Hidden from the listing, the sidecar is not in what a list of entries
        /// hands over, and it still has to land where its file did.
        @Test func aSidecarFoldsOntoItsFile() async throws {
            let state = try await open("gbk_sidecar.zip")
            #expect(tree(of: state) == ["中文目录", "中文目录/你好世界.txt", "中文目录/说明.txt"])

            let folder = try temporaryFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            await extractAll(state, to: folder)

            #expect(try files(in: folder) == sidecarFiles)
            let file = folder.appendingPathComponent("中文目录/你好世界.txt")
            #expect(getxattr(file.path, "com.macpacker.test", nil, 0, 0, XATTR_NOFOLLOW) > 0)
        }

        /// A Save As carries the decoy across by its stored path, which is the
        /// one place that looks up an entry the listing leaves out.
        @Test func aSaveAsKeepsWhatLooksLikeASidecar() async throws {
            let folder = try temporaryFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let state = try await open("gbk_sidecar.zip")

            try await save(state, to: folder.appendingPathComponent("copy.zip"))
            #expect(state.error == nil)

            let out = folder.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            await extractAll(state, to: out)
            #expect(try files(in: out) == sidecarFiles)
        }

        // MARK: Which encoding

        @Test(arguments: engines, [
            ("gbk.zip", ArchiveNameEncoding.gb18030),
            ("big5.zip", .big5),
            ("shiftjis.zip", .shiftJIS),
            ("cp949.zip", .korean),
            ("cp850.zip", .dosLatin),
            ("cp866.zip", .dosCyrillic),
            ("gbk.tar", .gb18030),
            ("gbk_cv.zip", .gb18030),
            ("gbk_forms.zip", .gb18030),
            ("big5_windows.zip", .big5),
            ("cp866_symbols.zip", .dosCyrillic),
            ("cp850_symbols.zip", .dosLatin),
        ])
        fileprivate func tellsWhatItReadTheNamesIn(
            selector: any ArchiveEngineSelectorProtocol, fixture: (String, ArchiveNameEncoding)
        ) async throws {
            let state = try await open(fixture.0, with: selector)
            #expect(state.nameEncoding == fixture.1)
        }

        /// XADMaster reads a path whole, and one that fails loses its folders, so
        /// an archive nothing can detect would open flat. The tree beats the name.
        @Test func automaticKeepsTheFoldersOnXAD() async throws {
            let state = try await open("cp1251.zip", with: ArchiveEngineSelectorXad())
            #expect(state.nameEncoding == .dosLatin)
            #expect(tree(of: state).map { $0.split(separator: "/").count }.sorted() == [1, 1, 2, 2])

            state.readNames(as: .windowsCyrillic)
            try await state.openTask?.value
            #expect(tree(of: state) == cp866Tree)
        }

        /// Nothing to choose: these say what their names are in.
        @Test(arguments: engines, ["defaultArchives/defaultArchive.zip", "defaultArchives/defaultArchive.7z", "encodings/unicode.7z"])
        fileprivate func anArchiveThatSaysHasNoEncoding(selector: any ArchiveEngineSelectorProtocol, file: String) async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: selector)
            let parts = file.split(separator: "/").map(String.init)
            let folder = try #require(Bundle.module.url(forResource: parts[0], withExtension: nil))
            state.open(url: folder.appendingPathComponent(parts[1]))
            try await state.openTask?.value

            #expect(state.error == nil)
            #expect(state.nameEncoding == nil)
        }

        /// Bytes that happen to be valid UTF-8 say nothing: 图片 in GBK reads ͼƬ, and
        /// only someone who sees the names can tell. The pick has to be there for them.
        @Test(arguments: engines, ["gbk_accident.zip", "gbk_accident.tar"])
        fileprivate func aNameThatOnlyLooksLikeUTF8TakesAPick(selector: any ArchiveEngineSelectorProtocol, file: String) async throws {
            let state = try await open(file, with: selector)
            #expect(state.nameEncoding == .utf8)
            #expect(tree(of: state) == ["ͼƬ.txt", "һЩ.txt"].sorted())

            state.readNames(as: .gb18030)
            try await state.openTask?.value

            #expect(state.error == nil)
            #expect(state.nameEncoding == .gb18030)
            #expect(tree(of: state) == ["图片.txt", "一些.txt"].sorted())

            let folder = try temporaryFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            await extractAll(state, to: folder)
            #expect(try files(in: folder) == ["图片.txt", "一些.txt"].sorted())
        }

        /// Real UTF-8 with nothing to say so, which is every zip a Mac writes: neither
        /// `ditto` nor `zip` sets the flag. It reads as it is, and says what it was read in.
        @Test(arguments: engines, [
            ("utf8_unflagged.zip", ["Größe.txt", "日本語.txt"]),
            ("../zip/utf_你好.zip", ["utf_你好.txt"]),
        ])
        fileprivate func unflaggedUTF8ReadsAsItIs(selector: any ArchiveEngineSelectorProtocol, fixture: (String, [String])) async throws {
            let state = try await open(fixture.0, with: selector)
            #expect(state.nameEncoding == .utf8)
            #expect(tree(of: state) == fixture.1.sorted())
        }

        // MARK: Picking one

        /// Nothing detects Windows-1251: the pick is what reads it, and an
        /// extraction has to go by the pick too.
        @Test(arguments: engines)
        fileprivate func aPickReadsTheNamesAndExtractsThem(selector: any ArchiveEngineSelectorProtocol) async throws {
            let state = try await open("cp1251.zip", with: selector)
            let detected = tree(of: state)
            #expect(detected != cp866Tree)
            #expect(state.chosenNameEncoding == nil)

            state.readNames(as: .windowsCyrillic)
            try await state.openTask?.value

            #expect(state.error == nil)
            #expect(state.chosenNameEncoding == .windowsCyrillic)
            #expect(state.nameEncoding == .windowsCyrillic)
            #expect(tree(of: state) == cp866Tree)

            let item = try #require(state.entries.values.first { $0.name == "Отчёт.txt" })
            let extracted = try await state.extractToTemp(item: item)
            defer { try? FileManager.default.removeItem(at: extracted) }
            #expect(extracted.lastPathComponent == "Отчёт.txt")

            let folder = try temporaryFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            await extractAll(state, to: folder)
            #expect(try files(in: folder) == cp866Tree)
        }

        /// Nothing detects these, so a wrong code page behind an entry would go
        /// unnoticed. The bytes are what Python's own codecs write, not Foundation's.
        @Test(arguments: [
            (ArchiveNameEncoding.dosCentralEuropean, [0x9D, 0xA2, 0x64, 0xAB] as [UInt8], "Łódź"),
            (.windowsCentralEuropean, [0xA3, 0xF3, 0x64, 0x9F], "Łódź"),
            (.dosGreek, [0x84, 0xA2, 0xA2, 0x9E, 0xA4, 0xA0, 0xA1, 0xE1], "Ελληνικά"),
            (.windowsGreek, [0xC5, 0xEB, 0xEB, 0xE7, 0xED, 0xE9, 0xEA, 0xDC], "Ελληνικά"),
            (.dosTurkish, [0x49, 0x9F, 0x8D, 0x6B], "Işık"),
            (.windowsTurkish, [0x49, 0xFE, 0xFD, 0x6B], "Işık"),
            (.dosHebrew, [0x92, 0x81, 0x98, 0x89, 0x9A], "עברית"),
            (.windowsHebrew, [0xF2, 0xE1, 0xF8, 0xE9, 0xFA], "עברית"),
            (.windowsArabic, [0xDA, 0xD1, 0xC8, 0xED], "عربي"),
            (.thai, [0xE4, 0xB7, 0xC2], "ไทย"),
            (.dosBaltic, [0x52, 0x8C, 0x67, 0x61], "Rīga"),
            (.windowsBaltic, [0x52, 0xEE, 0x67, 0x61], "Rīga"),
        ])
        fileprivate func aCodePageNothingDetectsReadsItsOwnBytes(entry: (ArchiveNameEncoding, [UInt8], String)) {
            #expect(entry.0.read(Data(entry.1), storedAs: "", validUTF8: .read) == entry.2)
        }

        /// A wrong encoding reads the names wrong, not the tree. Read a whole path
        /// at a time, one that fails stays as stored while the entry of its
        /// folder reads, and the folder shows twice. What the list shows is also
        /// what lands, however wrong.
        @Test(arguments: [
            ("cp866.zip", ArchiveNameEncoding.shiftJIS),
            ("cp1251.zip", .shiftJIS),
            ("gbk.zip", .big5),
            ("gbk.zip", .shiftJIS),
            ("gbk.zip", .korean),
            ("big5.zip", .gb18030),
            ("shiftjis.zip", .korean),
            ("cp949.zip", .big5),
        ])
        fileprivate func aWrongPickKeepsTheTree(fixture: (String, ArchiveNameEncoding)) async throws {
            let state = try await open(fixture.0)
            func shape(_ tree: [String]) -> [Int] {
                tree.map { $0.split(separator: "/").count }.sorted()
            }
            let right = shape(tree(of: state))

            state.readNames(as: fixture.1)
            try await state.openTask?.value

            #expect(state.error == nil)
            #expect(shape(tree(of: state)) == right)

            let folder = try temporaryFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            await extractAll(state, to: folder)
            #expect(try files(in: folder) == tree(of: state))
        }

        @Test(arguments: engines)
        fileprivate func automaticGoesBackToDetection(selector: any ArchiveEngineSelectorProtocol) async throws {
            let state = try await open("gbk.zip", with: selector)

            state.readNames(as: .big5)
            try await state.openTask?.value
            #expect(tree(of: state) != gbkTree.sorted())

            state.readNames(as: nil)
            try await state.openTask?.value
            #expect(state.chosenNameEncoding == nil)
            #expect(state.nameEncoding == .gb18030)
            #expect(tree(of: state) == gbkTree.sorted())
        }

        /// UTF-8 is on the list for a detection that got it wrong: the names
        /// stay what they were before anything was decoded.
        @Test(arguments: engines)
        fileprivate func aPickOfUTF8LeavesTheNames(selector: any ArchiveEngineSelectorProtocol) async throws {
            let state = try await open("gbk.zip", with: selector)

            state.readNames(as: .utf8)
            try await state.openTask?.value

            #expect(state.error == nil)
            #expect(state.nameEncoding == .utf8)
            #expect(tree(of: state) != gbkTree.sorted())
        }

        @Test func aPickEndsWithTheArchive() async throws {
            let state = try await open("gbk.zip")
            state.readNames(as: .big5)
            try await state.openTask?.value

            state.open(url: try url(of: "shiftjis.zip"))
            try await state.openTask?.value

            #expect(state.chosenNameEncoding == nil)
            #expect(state.nameEncoding == .shiftJIS)
        }

        /// Reading the names again lists the archive anew, which would take
        /// pending changes with it.
        @Test func aPickWaitsForPendingChanges() async throws {
            let state = try await open("gbk.zip")
            let folder = try temporaryFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let file = folder.appendingPathComponent("added.txt")
            try Data("added".utf8).write(to: file)
            #expect(await state.add(url: file).value)

            state.readNames(as: .big5)

            #expect(state.chosenNameEncoding == nil)
            #expect(state.hasPendingChanges)
        }

        /// Reading the names again clears what was extracted to show it.
        @Test func aPickClosesThePreview() async throws {
            let state = try await open("gbk.zip")
            state.previewItemUrl = FileManager.default.temporaryDirectory.appendingPathComponent("shown.txt")

            state.readNames(as: .big5)

            #expect(state.previewItemUrl == nil)
        }

        /// It would clean the temp folder an extraction is writing to.
        @Test func aPickWaitsForAnExtraction() async throws {
            let state = try await open("gbk.zip")
            let folder = try temporaryFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let item = try #require(state.entries.values.first { $0.type == .file })

            await withCheckedContinuation { continuation in
                state.onStatusChange = { status in
                    if status == .done { continuation.resume() }
                }
                state.extract(items: [item], to: folder, smart: false)
                state.readNames(as: .big5)
                #expect(state.chosenNameEncoding == nil)
            }
            state.onStatusChange = nil

            state.readNames(as: .big5)
            #expect(state.chosenNameEncoding == .big5)
            try await state.openTask?.value
        }

        /// A pick covers every name the archive leaves open, also one that happens
        /// to be valid UTF-8: `сон` in CP866 is one Sundanese letter. The name the
        /// archive declares stays, whatever was picked.
        @Test(arguments: engines)
        fileprivate func aPickReachesEveryNameTheArchiveLeavesOpen(selector: any ArchiveEngineSelectorProtocol) async throws {
            let state = try await open("cp866_lookalike.zip", with: selector)
            state.readNames(as: .dosCyrillic)
            try await state.openTask?.value

            let names = ["Café.txt", "Документы", "Документы/Отчёт.txt", "сад", "сад/том.txt", "сон.txt"].sorted()
            #expect(tree(of: state) == names)

            let folder = try temporaryFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            await extractAll(state, to: folder)
            #expect(try files(in: folder) == names)
        }

        /// The archive stays with the engine that read it, as it does across a
        /// save. Settings may have moved on to one that cannot read it at all.
        @Test func aPickStaysWithTheEngineThatReadTheArchive() async throws {
            let selector = ChangingSelector()
            let state = try await open("gbk.zip", with: selector)
            selector.configured = .swc

            state.readNames(as: .big5)
            try await state.openTask?.value

            #expect(state.error == nil)
            #expect(state.activeEngine == .`7zip`)
            #expect(state.nameEncoding == .big5)
        }

        // MARK: Passwords

        @Test func aPickDoesNotAskForThePasswordAgain() async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            let answers = Answers(["secret"])
            state.passwordProvider = { _ in await answers.next() }
            state.open(url: try url(of: "gbk_password.zip"))
            try await state.openTask?.value
            #expect(await answers.asked == 1)

            state.readNames(as: .big5)
            try await state.openTask?.value

            #expect(state.error == nil)
            #expect(await answers.asked == 1)
        }

        /// XADMaster opens the archive anew for each password tried, and what is
        /// opened anew has to be told the encoding again, or the entry the
        /// extraction names is no longer in it.
        @Test(arguments: engines)
        fileprivate func anotherPasswordKeepsTheNames(selector: any ArchiveEngineSelectorProtocol) async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: selector)
            let answers = Answers(["wrong", "secret"])
            state.passwordProvider = { _ in await answers.next() }
            state.open(url: try url(of: "gbk_password.zip"))
            try await state.openTask?.value

            let item = try #require(state.entries.values.first { $0.name == "你好世界.txt" })
            let extracted = try await state.extractToTemp(item: item)
            defer { try? FileManager.default.removeItem(at: extracted) }

            #expect(extracted.lastPathComponent == "你好世界.txt")
            #expect(try String(contentsOf: extracted, encoding: .utf8) == "Locked behind a GBK name.\n")
        }

        // MARK: Saving

        private func copy(_ file: String, to folder: URL) throws -> URL {
            let target = folder.appendingPathComponent(file)
            try FileManager.default.copyItem(at: try url(of: file), to: target)
            return target
        }

        /// What a save keeps it keeps as stored, in the old code page. What it
        /// adds is UTF-8, flagged as such, and reads as that next to the rest.
        @Test func aSaveKeepsTheNamesAsStored() async throws {
            let folder = try temporaryFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let archive = try copy("gbk.zip", to: folder)
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.open(url: archive)
            try await state.openTask?.value

            let file = folder.appendingPathComponent("新建文档.txt")
            try Data("added".utf8).write(to: file)
            #expect(await state.add(url: file).value)
            try await save(state)

            #expect(state.error == nil)
            #expect(state.nameEncoding == .gb18030)
            #expect(tree(of: state) == (gbkTree + ["新建文档.txt"]).sorted())

            let stored = try Data(contentsOf: archive)
            let gbk = try #require("你好世界".data(using: ArchiveNameEncoding.gb18030.stringEncoding))
            #expect(stored.range(of: gbk) != nil)
        }

        /// A Save As writes every entry again, and the new archive says what its
        /// names are in. They had better be the ones the window shows: this is
        /// where mojibake would become permanent.
        @Test(arguments: [("gbk.zip", nil, gbkTree.sorted()), ("cp1251.zip", ArchiveNameEncoding.windowsCyrillic, cp866Tree)])
        fileprivate func aSaveAsWritesTheNamesTheWindowShows(fixture: (String, ArchiveNameEncoding?, [String])) async throws {
            let folder = try temporaryFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.open(url: try copy(fixture.0, to: folder))
            try await state.openTask?.value
            if let picked = fixture.1 {
                state.readNames(as: picked)
                try await state.openTask?.value
            }

            try await save(state, to: folder.appendingPathComponent("copy.zip"))

            #expect(state.error == nil)
            #expect(state.nameEncoding == nil)
            #expect(tree(of: state) == fixture.2)
        }

        /// `../中文.txt`, `./中文.txt` and `中文.txt` land on one path, and a Save As
        /// extracts everything before writing it again. Each has to go in with
        /// its own content, or one file's bytes quietly replace the others'.
        @Test func aSaveAsKeepsFilesThatLandOnOnePath() async throws {
            let folder = try temporaryFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let copy = folder.appendingPathComponent("copy.zip")
            let state = try await open("gbk_twins.zip")

            try await save(state, to: copy)
            #expect(state.error == nil)

            let archive = try SevenZipArchive(url: copy)
            var contents: [String] = []
            for entry in try archive.entries {
                let out = folder.appendingPathComponent("entry-\(entry.index)")
                try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
                let landed = try #require(try archive.extract(index: entry.index, to: out)[entry.index])
                contents.append(try String(contentsOf: landed, encoding: .utf8))
            }
            #expect(contents.sorted() == ["from above", "from here", "plain"])
        }

        /// The pick is the window's, so a save reopening the archive keeps it.
        @Test func aSaveKeepsThePick() async throws {
            let folder = try temporaryFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.open(url: try copy("cp1251.zip", to: folder))
            try await state.openTask?.value
            state.readNames(as: .windowsCyrillic)
            try await state.openTask?.value

            let file = folder.appendingPathComponent("added.txt")
            try Data("added".utf8).write(to: file)
            #expect(await state.add(url: file).value)
            try await save(state)

            #expect(state.chosenNameEncoding == .windowsCyrillic)
            #expect(tree(of: state) == (cp866Tree + ["added.txt"]).sorted())
        }

        /// `文档` alone reads as Korean, and a save that leaves only that changes
        /// no byte of it.
        @Test func aSaveDoesNotChangeHowTheNamesRead() async throws {
            let folder = try temporaryFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.open(url: try copy("gbk_flip.zip", to: folder))
            try await state.openTask?.value
            #expect(state.nameEncoding == .gb18030)

            let others = try #require(state.childItems?.filter { $0.name != "文档" })
            state.remove(items: others)
            try await save(state)

            #expect(state.nameEncoding == .gb18030)
            #expect(tree(of: state) == ["文档"])
        }

        /// To the archive around it, an archive is one entry, so what the names
        /// inside it are read as cannot reach a file. It is the outer archive's
        /// names a Save As writes, as the pick reads them.
        @Test func aSaveLeavesAnArchiveInsideAlone() async throws {
            let folder = try temporaryFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let archive = try copy("nested_gbk.zip", to: folder)

            func inner(of path: URL) async throws -> Data {
                let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
                state.open(url: path)
                try await state.openTask?.value
                let item = try #require(state.entries.values.first { $0.name == "inner.zip" })
                let extracted = try await state.extractToTemp(item: item)
                defer { try? FileManager.default.removeItem(at: extracted) }
                return try Data(contentsOf: extracted)
            }
            let before = try await inner(of: archive)

            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            state.open(url: archive)
            try await state.openTask?.value
            state.readNames(as: .windowsCyrillic)
            try await state.openTask?.value
            let nested = try #require(state.entries.values.first { $0.name == "inner.zip" })
            try await state.openAsync(item: nested)
            #expect(tree(of: state).contains("inner.zip/НјЖ¬"))
            #expect(!state.canAddHere)
            #expect(!state.canRemove((nested.children ?? []).compactMap { state.entries[$0] }))

            let copy = folder.appendingPathComponent("copy.zip")
            try await save(state, to: copy)
            #expect(try await inner(of: copy) == before)

            let reopened = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: ArchiveEngineSelector7zip())
            reopened.open(url: copy)
            try await reopened.openTask?.value
            #expect(tree(of: reopened) == ["inner.zip", "Отчёт.txt"].sorted())
        }

        // MARK: Detection

        private func bytes(_ names: [String], in encoding: ArchiveNameEncoding) throws -> [Data] {
            try names.map { try #require($0.data(using: encoding.stringEncoding)) }
        }

        /// Three names at a time, as few as a small archive has. One name alone
        /// is sometimes too little to go on, and the pick is there for that.
        @Test(arguments: [
            (ArchiveNameEncoding.gb18030, [
                "新建文件夹", "工作总结.docx", "项目计划书.pdf", "财务报表.xlsx", "合同扫描件.pdf", "会议纪要.doc",
                "图片/风景照.jpg", "音乐/周杰伦.mp3", "安装说明.txt", "数据备份.sql", "客户名单.xls", "源代码"]),
            // Chinese that stays in the bytes of everyday Korean from start to end.
            (.gb18030, [
                "个人简历模板.doc", "简历模板.doc", "报名表.xls", "年度报告.pdf", "计划表.xls", "价格表.xls",
                "课程表.xls", "名单表.xls", "个人简历.doc", "报告模板.doc", "年度计划.doc", "报名表格.doc"]),
            (.big5, [
                "新增資料夾", "工作報告.docx", "專案計畫書.pdf", "財務報表.xlsx", "合約掃描檔.pdf", "會議記錄.doc",
                "圖片/風景.jpg", "音樂/周杰倫.mp3", "安裝說明.txt", "資料備份.sql", "客戶名單.xls", "原始碼"]),
            (.shiftJIS, [
                "新しいフォルダー", "議事録.docx", "請求書.pdf", "見積書.xlsx", "契約書.pdf", "報告書.doc",
                "画像/風景.jpg", "音楽/アルバム.mp3", "インストール手順.txt", "データ/バックアップ.sql", "顧客リスト.xls", "ソースコード"]),
            (.korean, [
                "새 폴더", "회의록.docx", "청구서.pdf", "견적서.xlsx", "계약서.pdf", "보고서.doc",
                "이미지/풍경.jpg", "음악/앨범.mp3", "설치방법.txt", "데이터/백업.sql", "고객명단.xls", "소스코드"]),
        ])
        fileprivate func tellsEastAsianNamesApart(encoding: ArchiveNameEncoding, names: [String]) throws {
            let names = try bytes(names, in: encoding)
            for start in 0...(names.count - 3) {
                #expect(ArchiveNameEncoding.detect(in: Array(names[start..<start + 3])) == encoding, "from name \(start)")
            }
        }

        /// Western names show one or two bytes above ASCII, and any of them has to
        /// be enough: a German's zip of one file is as common as any.
        @Test(arguments: [
            "Müller.txt", "Größe.txt", "Déjà vu.txt", "España/niño.doc", "Übersicht.pdf", "Café.txt", "résumé.pdf",
            "Straße.txt", "MÜLLER.TXT", "Änderung.doc", "Köln/Dom.jpg", "Señor (1).doc",
            "São Paulo.txt", "Søren.txt", "Ángel.doc", "Ålesund.jpg", "§ 34 Änderung.pdf", "Größe 20°.txt",
        ])
        fileprivate func takesOneWesternNameForWestern(name: String) throws {
            #expect(ArchiveNameEncoding.detect(in: try bytes([name], in: .dosLatin)) == .dosLatin)
        }

        /// A Russian's zip of one file, the same: any name has to be enough.
        @Test(arguments: [
            "Документы.txt", "Отчёт.doc", "Новая папка", "Фотографии/лето.jpg", "Договор.pdf", "Счёт на оплату.xlsx",
            "Презентация.ppt", "Музыка.mp3", "Инструкция.txt", "ДОГОВОР.PDF", "Прайс-лист.xlsx", "Фото_2023.jpg",
            "Акт сверки.xls", "Отчёт (1).doc", "Письмо.txt", "Приказ №15.doc", "Счёт №3.xls",
        ])
        fileprivate func takesOneRussianNameForRussian(name: String) throws {
            #expect(ArchiveNameEncoding.detect(in: try bytes([name], in: .dosCyrillic)) == .dosCyrillic)
        }

        /// The East Asian names that come closest to an alphabet: a lead byte that
        /// is `â` in CP850 and `Г` in CP866, and a second byte in ASCII or among
        /// the small letters of CP866.
        @Test(arguments: [
            "データ.txt", "ソフト.txt", "テスト.txt", "アルバム.mp3", "ファイル", "メール.txt",
            "はじめに.txt", "あいうえお.txt", "ドキュメント", "おしらせ.doc", "ひらがな.txt", "まつり.jpg",
        ])
        fileprivate func doesNotTakeJapaneseForAnAlphabet(name: String) throws {
            let found = ArchiveNameEncoding.detect(in: try bytes([name], in: .shiftJIS))
            #expect(found != .dosLatin)
            #expect(found != .dosCyrillic)
        }

        /// A name that fits no encoding does not decide for the ones that do.
        @Test(arguments: [
            (ArchiveNameEncoding.gb18030, ["新建文件夹", "工作总结.docx", "项目计划书.pdf"]),
            (.big5, ["新增資料夾", "工作報告.docx", "專案計畫書.pdf"]),
            (.shiftJIS, ["新しいフォルダー", "議事録.docx", "請求書.pdf"]),
            (.korean, ["새 폴더", "회의록.docx", "청구서.pdf"]),
        ])
        fileprivate func oneBrokenNameChangesNothing(encoding: ArchiveNameEncoding, names: [String]) throws {
            let broken = Data([0xFF, 0xFF, 0x2E, 0x74, 0x78, 0x74])
            #expect(ArchiveNameEncoding.detect(in: try bytes(names, in: encoding) + [broken]) == encoding)
        }

        /// Every encoding the menu offers is one macOS can name and read.
        @Test(arguments: ArchiveNameEncoding.allCases)
        fileprivate func macOSKnowsTheEncoding(encoding: ArchiveNameEncoding) {
            #expect(!encoding.localizedName.isEmpty)
            #expect(String(data: Data("name".utf8), encoding: encoding.stringEncoding) == "name")
        }
    }
}

/// Hands out passwords in turn, and counts how often it was asked.
private actor Answers {
    private let answers: [String]
    private(set) var asked = 0

    init(_ answers: [String]) { self.answers = answers }

    func next() -> String? {
        defer { asked += 1 }
        return asked < answers.count ? answers[asked] : answers.last
    }
}
