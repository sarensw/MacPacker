//
//  MacPackerUITests.swift
//  MacPackerUITests
//
//  Created by Stephan Arenswald on 16.07.26.
//
//  UI tests for editing zip archives: delete entries from an existing zip
//  and create a new zip via the Finder "Compress" action. All fixtures are
//  generated at test time inside the app's sandbox container — no checked-in
//  test archives are touched.
//

import XCTest

final class MacPackerUITests: XCTestCase {

    /// Bundle id of the debug app under test (drives container + url scheme).
    private let appBundleId = "com.sarensx.MacPacker.debug"
    private let appUrlScheme = "app.macpacker.debug"

    /// Fixture area: the runner's home (its own container under XCUITest).
    /// The app under test can READ here but not write — saving triggers the
    /// folder-access prompt, which the tests confirm like a user would. That
    /// also exercises the read-only-archive save recovery on purpose.
    private var fixtureBase: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacPackerUITests")
    }

    /// Confirms a powerbox folder-access panel when it appears: the panel's
    /// default button carries the given title, Return triggers it. Scoped to
    /// windows — a bare `buttons[...]` query can resolve to an unclickable
    /// Touch Bar element.
    private func confirmAccessPanel(_ app: XCUIApplication, button: String, timeout: TimeInterval = 10) {
        let grant = app.windows.buttons[button].firstMatch
        if grant.waitForExistence(timeout: timeout) {
            app.typeKey(.return, modifierFlags: [])
        }
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    @discardableResult
    private func run(_ tool: String, _ args: [String], cwd: URL? = nil) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertEqual(p.terminationStatus, 0, "\(tool) \(args.joined(separator: " ")): \(text)")
        return text
    }

    /// Fresh work dir for one test.
    private func makeWorkDir(_ name: String) throws -> URL {
        let dir = fixtureBase.appendingPathComponent("macpacker-uitests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Entry names in a zip, via the independent system tool.
    private func zipEntries(_ zip: URL) throws -> Set<String> {
        let out = try run("/usr/bin/unzip", ["-Z1", zip.path])
        return Set(out.split(separator: "\n").map(String.init))
    }

    private func launchApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + ["-DisableUpdateChecks", "YES"]
        app.launch()
        return app
    }

    // MARK: - Tests

    /// A file can be deleted from an existing zip through the UI:
    /// select row → toolbar Delete → toolbar Save → zip on disk updated.
    func testDeleteFileFromZip() throws {
        // fixture zip built with the system tool
        let dir = try makeWorkDir("delete")
        defer { try? FileManager.default.removeItem(at: dir) }
        try "one".write(to: dir.appendingPathComponent("one.txt"), atomically: true, encoding: .utf8)
        try "two".write(to: dir.appendingPathComponent("two.txt"), atomically: true, encoding: .utf8)
        let zip = dir.appendingPathComponent("fixture.zip")
        try run("/usr/bin/zip", [zip.path, "one.txt", "two.txt"], cwd: dir)

        let app = launchApp(arguments: ["-ArchivePath", zip.path])

        // the archive window shows both entries
        let victim = app.staticTexts["one.txt"]
        XCTAssertTrue(victim.waitForExistence(timeout: 10), "archive did not load")
        XCTAssertTrue(app.staticTexts["two.txt"].exists)

        // select + delete
        victim.click()
        let deleteButton = app.buttons["Delete"].firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.click()

        // the row disappears from the table immediately
        XCTAssertTrue(victim.waitForNonExistence(timeout: 5), "deleted row still shown")

        // ⌘S (File > Save Archive) applies the change to the file; the
        // archive was opened without a write grant, so the app asks for
        // folder access first — confirm it
        app.typeKey("s", modifierFlags: .command)
        confirmAccessPanel(app, button: "Grant Access")

        // poll the file until the entry is gone (save is async)
        let deadline = Date().addingTimeInterval(15)
        var entries = try zipEntries(zip)
        while entries.contains("one.txt") && Date() < deadline {
            usleep(300_000)
            entries = try zipEntries(zip)
        }
        XCTAssertFalse(entries.contains("one.txt"), "one.txt still in zip: \(entries)")
        XCTAssertTrue(entries.contains("two.txt"), "two.txt lost: \(entries)")

        // archive is still valid
        try run("/usr/bin/unzip", ["-t", zip.path])
        app.terminate()
    }

    /// A folder (with its contents) can be deleted from a zip through the UI.
    func testDeleteFolderFromZip() throws {
        let dir = try makeWorkDir("delete-folder")
        defer { try? FileManager.default.removeItem(at: dir) }
        let sub = dir.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "in folder".write(to: sub.appendingPathComponent("inner.txt"), atomically: true, encoding: .utf8)
        try "keep".write(to: dir.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)
        let zip = dir.appendingPathComponent("fixture.zip")
        try run("/usr/bin/zip", ["-r", zip.path, "folder", "keep.txt"], cwd: dir)

        let app = launchApp(arguments: ["-ArchivePath", zip.path])

        let folderRow = app.staticTexts["folder"]
        XCTAssertTrue(folderRow.waitForExistence(timeout: 10), "archive did not load")

        folderRow.click()
        app.buttons["Delete"].firstMatch.click()
        XCTAssertTrue(folderRow.waitForNonExistence(timeout: 5))
        app.typeKey("s", modifierFlags: .command)
        confirmAccessPanel(app, button: "Grant Access")

        let deadline = Date().addingTimeInterval(15)
        var entries = try zipEntries(zip)
        while entries.contains(where: { $0.hasPrefix("folder") }) && Date() < deadline {
            usleep(300_000)
            entries = try zipEntries(zip)
        }
        XCTAssertFalse(entries.contains { $0.hasPrefix("folder") }, "folder still in zip: \(entries)")
        XCTAssertTrue(entries.contains("keep.txt"))
        try run("/usr/bin/unzip", ["-t", zip.path])
        app.terminate()
    }

    /// A new zip with a new file is created through the Finder "Compress to"
    /// action (url scheme → folder-access prompt → zip appears next to the
    /// file). Exercises the same path the Finder context menu uses.
    func testCompressCreatesNewZip() throws {
        let dir = try makeWorkDir("compress")
        defer { try? FileManager.default.removeItem(at: dir) }
        let payload = dir.appendingPathComponent("hello.txt")
        try "hello zip".write(to: payload, atomically: true, encoding: .utf8)

        // launch with a dummy archive so the welcome window stays away
        let dummyZip = dir.appendingPathComponent("dummy.zip")
        try run("/usr/bin/zip", [dummyZip.path, "hello.txt"], cwd: dir)
        let app = launchApp(arguments: ["-ArchivePath", dummyZip.path])
        XCTAssertTrue(app.staticTexts["hello.txt"].waitForExistence(timeout: 10))

        // fire the Finder action: compress hello.txt in dir
        var comps = URLComponents(string: "\(appUrlScheme)://compress")!
        comps.queryItems = [
            URLQueryItem(name: "files", value: payload.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)),
            URLQueryItem(name: "target", value: dir.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)),
        ]
        NSWorkspace.shared.open(comps.url!)

        // the sandbox asks once for folder access — confirm the prompt
        confirmAccessPanel(app, button: "Give access to MacPacker")

        // the zip appears next to the file and contains it
        let created = dir.appendingPathComponent("hello.zip")
        let deadline = Date().addingTimeInterval(20)
        while !FileManager.default.fileExists(atPath: created.path) && Date() < deadline {
            usleep(300_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: created.path), "hello.zip was not created")

        let entries = try zipEntries(created)
        XCTAssertTrue(entries.contains("hello.txt"), "hello.txt missing: \(entries)")
        try run("/usr/bin/unzip", ["-t", created.path])
        app.terminate()
    }
}
