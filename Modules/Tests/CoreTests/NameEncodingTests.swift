//
//  NameEncodingTests.swift
//  Modules
//
//  An archive that does not say what its names are written in shows them as
//  they were meant, and extracts them under those names (#373).
//

import Foundation
import Testing
@testable import Core

/// The engines that read these formats; 7-Zip is the default for all of them.
private let engines: [any ArchiveEngineSelectorProtocol] = [ArchiveEngineSelector7zip(), ArchiveEngineSelectorXad()]

/// `gbk_sidecar.zip` on disk: the sidecar folded, the decoy still there.
private let sidecarFiles = ["中文目录", "中文目录/._说明.txt", "中文目录/你好世界.txt", "中文目录/说明.txt"].sorted()

private let cp866Tree = ["Документы", "Документы/Отчёт.txt", "Новая папка", "Новая папка/Договор.txt"].sorted()

/// A fixture from `TestArchives/encodings` and the tree it holds.
private struct Fixture: Sendable, CustomTestStringConvertible {
    let file: String
    let tree: [String]
    var testDescription: String { file }
}

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
    Fixture(file: "gbk.tar", tree: [
        "中文目录", "中文目录/你好世界.txt", "图片", "图片/风景.txt", "一些.txt"]),
]

extension AllCoreTests {
    @MainActor struct NameEncodingTests {
        private func url(of file: String) throws -> URL {
            try #require(Bundle.module.url(forResource: "encodings", withExtension: nil))
                .appendingPathComponent(file)
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

            await state.save(to: folder.appendingPathComponent("copy.zip"))?.value
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
        ])
        fileprivate func tellsWhatItReadTheNamesIn(
            selector: any ArchiveEngineSelectorProtocol, fixture: (String, ArchiveNameEncoding)
        ) async throws {
            let state = try await open(fixture.0, with: selector)
            #expect(state.nameEncoding == fixture.1)
        }

        /// Nothing to choose: these say what their names are in.
        @Test(arguments: engines, ["zip/utf_你好.zip", "defaultArchives/defaultArchive.zip", "defaultArchives/defaultArchive.7z"])
        fileprivate func anArchiveThatSaysHasNoEncoding(selector: any ArchiveEngineSelectorProtocol, file: String) async throws {
            let state = ArchiveState(catalog: ArchiveTypeCatalog(), engineSelector: selector)
            let parts = file.split(separator: "/").map(String.init)
            let folder = try #require(Bundle.module.url(forResource: parts[0], withExtension: nil))
            state.open(url: folder.appendingPathComponent(parts[1]))
            try await state.openTask?.value

            #expect(state.error == nil)
            #expect(state.nameEncoding == nil)
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
            await state.save()?.value

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

            await state.save(to: folder.appendingPathComponent("copy.zip"))?.value

            #expect(state.error == nil)
            #expect(state.nameEncoding == nil)
            #expect(tree(of: state) == fixture.2)
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
            await state.save()?.value

            #expect(state.chosenNameEncoding == .windowsCyrillic)
            #expect(tree(of: state) == (cp866Tree + ["added.txt"]).sorted())
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
            "São Paulo.txt", "Søren.txt", "Ángel.doc", "Ålesund.jpg",
        ])
        fileprivate func takesOneWesternNameForWestern(name: String) throws {
            #expect(ArchiveNameEncoding.detect(in: try bytes([name], in: .dosLatin)) == .dosLatin)
        }

        /// A Russian's zip of one file, the same: any name has to be enough.
        @Test(arguments: [
            "Документы.txt", "Отчёт.doc", "Новая папка", "Фотографии/лето.jpg", "Договор.pdf", "Счёт на оплату.xlsx",
            "Презентация.ppt", "Музыка.mp3", "Инструкция.txt", "ДОГОВОР.PDF", "Прайс-лист.xlsx", "Фото_2023.jpg",
            "Акт сверки.xls", "Отчёт (1).doc", "Письмо.txt",
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
