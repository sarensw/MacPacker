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
    /// select row → toolbar Delete → ⌘S Save → zip on disk updated.
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

        // status bar counts the two real entries (not the synthetic root)
        XCTAssertTrue(app.staticTexts["2 items"].waitForExistence(timeout: 5),
                      "expected '2 items' in the status bar")

        // select + delete
        victim.click()
        let deleteButton = app.buttons["Delete"].firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.click()

        // the row disappears from the table immediately
        XCTAssertTrue(victim.waitForNonExistence(timeout: 5), "deleted row still shown")

        // ⌘S (File > Save) applies the change to the file; the
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

        // after the reload the count reflects the single remaining entry
        XCTAssertTrue(app.staticTexts["1 item"].waitForExistence(timeout: 10),
                      "expected '1 item' in the status bar after delete+save")

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

    /// An empty window shows the home screen, lists the archives opened before,
    /// and opening one from that list loads it in that very window.
    ///
    /// The empty window is opened with ⌘⇧N from a window launched via
    /// `-ArchivePath`: that both seeds the recents list and keeps the welcome
    /// window (always shown on a plain dev launch) out of the way. Depending on
    /// the system's window-tabbing setting it may come up as a tab — the
    /// assertions look at content, not at window count, so either is fine.
    func testHomeScreenOpensArchiveFromRecents() throws {
        let dir = try makeWorkDir("recents")
        defer { try? FileManager.default.removeItem(at: dir) }
        try "one".write(to: dir.appendingPathComponent("one.txt"), atomically: true, encoding: .utf8)
        let zip = dir.appendingPathComponent("recents-fixture.zip")
        try run("/usr/bin/zip", [zip.path, "one.txt"], cwd: dir)

        let app = launchApp(arguments: ["-ArchivePath", zip.path])
        XCTAssertTrue(app.staticTexts["one.txt"].waitForExistence(timeout: 15), "archive did not load")

        // New MacPacker Window → empty → home screen
        app.typeKey("n", modifierFlags: [.command, .shift])
        // the start-page cards carry title + subtitle in one AX label
        let openButton = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Open Archive…")).firstMatch
        XCTAssertTrue(openButton.waitForExistence(timeout: 10), "the empty window does not show the home screen")

        // the archive just opened is listed under Recent, and opening it from
        // there replaces the home screen with the archive
        let recent = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "recents-fixture.zip")).firstMatch
        XCTAssertTrue(recent.waitForExistence(timeout: 5), "the archive is not listed under Recent")
        recent.click()
        XCTAssertTrue(openButton.waitForNonExistence(timeout: 15), "the recent archive did not open in that window")
        XCTAssertTrue(app.staticTexts["one.txt"].waitForExistence(timeout: 15), "the archive content is not shown")
        app.terminate()
    }

    /// Dragging a file from Finder onto the upper half of an editable archive adds
    /// it — the drop zones replaced the old ⌥-modifier gesture, so the plain drag
    /// has to land in the archive without any key held.
    func testDragFromFinderAddsToArchive() throws {
        let dir = try makeWorkDir("drag")
        defer { try? FileManager.default.removeItem(at: dir) }
        try "one".write(to: dir.appendingPathComponent("one.txt"), atomically: true, encoding: .utf8)
        let zip = dir.appendingPathComponent("fixture.zip")
        try run("/usr/bin/zip", [zip.path, "one.txt"], cwd: dir)
        try "dropped".write(to: dir.appendingPathComponent("dropped.txt"), atomically: true, encoding: .utf8)

        let app = launchApp(arguments: ["-ArchivePath", zip.path])
        XCTAssertTrue(app.staticTexts["one.txt"].waitForExistence(timeout: 15), "archive did not load")

        // a Finder window on the fixture folder is the drag source
        NSWorkspace.shared.open(dir)
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        // list view shows names as text fields (they double as the rename field)
        let source = finder.textFields.matching(NSPredicate(format: "value == %@", "dropped.txt")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 15), "Finder does not show the file to drag")

        // upper half of the window = the "add" zone
        let target = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1, thenDragTo: target)

        XCTAssertTrue(app.staticTexts["dropped.txt"].waitForExistence(timeout: 15),
                      "the dropped file was not added to the archive")
        // the zones are for the drag only — `dropUpdated` keeps firing after the
        // drop, so they must not re-arm themselves once the file has landed
        XCTAssertTrue(app.staticTexts["Open in a new window"].waitForNonExistence(timeout: 5),
                      "the drop zones stayed on screen after the drop")

        // lower half = "open in a new window"; a plain file starts a new archive
        // there. Let the previous drag settle first — back-to-back drags out of
        // the same Finder row drop the second one.
        sleep(1)
        let openZone = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1, thenDragTo: openZone)
        XCTAssertTrue(app.staticTexts["New Archive"].waitForExistence(timeout: 15),
                      "the open zone did not start a new archive for the plain file")
        XCTAssertTrue(app.staticTexts["Open in a new window"].waitForNonExistence(timeout: 5),
                      "the drop zones stayed on screen after the drop")
        app.terminate()
    }

    /// Issue #141: the toolbar display mode picked from the toolbar's context menu
    /// survives a relaunch. Drives the reported repro in both directions, so the
    /// result can't come from state a previous run left behind.
    ///
    /// `-ArchivePath` matters beyond loading a fixture: it suppresses the welcome
    /// window, so the archive window is the one the right-click lands on.
    func testToolbarDisplayModePersistsAcrossRelaunch() throws {
        let dir = try makeWorkDir("toolbar")
        defer { try? FileManager.default.removeItem(at: dir) }
        try "one".write(to: dir.appendingPathComponent("one.txt"), atomically: true, encoding: .utf8)
        let zip = dir.appendingPathComponent("fixture.zip")
        try run("/usr/bin/zip", [zip.path, "one.txt"], cwd: dir)

        // the toolbar grows when it has to make room for the item titles — SwiftUI
        // toolbar labels aren't exposed as their own AX text, so height is the signal
        func launchAndMeasure() -> (XCUIApplication, CGFloat) {
            let app = launchApp(arguments: ["-ArchivePath", zip.path])
            XCTAssertTrue(app.staticTexts["one.txt"].waitForExistence(timeout: 15), "archive did not load")
            let toolbar = app.windows.toolbars.firstMatch
            XCTAssertTrue(toolbar.waitForExistence(timeout: 5), "no toolbar")
            return (app, toolbar.frame.height)
        }
        func chooseDisplayMode(_ app: XCUIApplication, _ item: String) -> CGFloat {
            app.windows.firstMatch
                .coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.0))
                .withOffset(CGVector(dx: 0, dy: 26))
                .rightClick()
            let menuItem = app.menuItems[item]
            XCTAssertTrue(menuItem.waitForExistence(timeout: 5), "no “\(item)” in the toolbar context menu")
            menuItem.click()
            sleep(1)
            return app.windows.toolbars.firstMatch.frame.height
        }

        // Icon Only first only to pin down a known starting point — the mode is then
        // changed again before every relaunch, so each restore assertion below is
        // preceded by a real change and can't pass on prefs a previous run left.
        let (first, _) = launchAndMeasure()
        let iconOnly = chooseDisplayMode(first, "Icon Only")
        let iconAndText = chooseDisplayMode(first, "Icon and Text")
        XCTAssertGreaterThan(iconAndText, iconOnly, "picking Icon and Text did not grow the toolbar")
        first.terminate()

        let (second, restoredIconAndText) = launchAndMeasure()
        XCTAssertEqual(restoredIconAndText, iconAndText, "Icon and Text did not survive the relaunch")
        XCTAssertEqual(chooseDisplayMode(second, "Icon Only"), iconOnly, "switching back to Icon Only did not shrink the toolbar")
        second.terminate()

        let (third, restoredIconOnly) = launchAndMeasure()
        XCTAssertEqual(restoredIconOnly, iconOnly, "Icon Only did not survive the relaunch")
        third.terminate()
    }
}
