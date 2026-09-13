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

    /// The search field sits at the trailing end of the toolbar (HIG), says
    /// "Search", and ⌘F puts the focus into it: typing then filters the archive
    /// instead of type-selecting in the table.
    func testCommandFFocusesTrailingToolbarSearch() throws {
        let dir = try makeWorkDir("search")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"),
                                                withIntermediateDirectories: true)
        try "one".write(to: dir.appendingPathComponent("one.txt"), atomically: true, encoding: .utf8)
        try "deep".write(to: dir.appendingPathComponent("sub/deep.txt"), atomically: true, encoding: .utf8)
        let zip = dir.appendingPathComponent("fixture.zip")
        try run("/usr/bin/zip", ["-r", zip.path, "one.txt", "sub"], cwd: dir)

        let app = launchApp(arguments: ["-ArchivePath", zip.path])
        XCTAssertTrue(app.staticTexts["one.txt"].waitForExistence(timeout: 15), "archive did not load")
        // nested — only a search across the whole archive brings it into view
        XCTAssertFalse(app.staticTexts["deep.txt"].exists)

        let search = app.windows.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "no search field in the toolbar")
        XCTAssertEqual(search.placeholderValue, "Search")
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertGreaterThan(search.frame.minX, delete.frame.maxX,
                             "the search field is not at the trailing end of the toolbar")

        app.typeKey("f", modifierFlags: .command)
        app.typeText("deep")

        XCTAssertTrue(app.staticTexts["deep.txt"].waitForExistence(timeout: 10),
                      "⌘F did not put the focus into the search field")
        XCTAssertTrue(app.staticTexts["one.txt"].waitForNonExistence(timeout: 10),
                      "non-matching entries are still shown")
        app.terminate()
    }

    /// The screenshot plan focuses the search field by accessibility identifier
    /// (`sandboxpilot.json`, scenario `04-search`), which SandboxPilotKit resolves
    /// from MacPacker's own accessibility tree. SwiftUI gives the field behind
    /// `.searchable` no identifier of its own, so `ArchiveWindowController`
    /// publishes one; if that stops happening the plan captures an unfocused field
    /// instead of failing, in fourteen languages at once.
    ///
    /// An identifier, not a label: labels are translated, identifiers are not.
    func testSearchFieldPublishesItsAccessibilityIdentifier() throws {
        let dir = try makeWorkDir("axid")
        defer { try? FileManager.default.removeItem(at: dir) }
        try "one".write(to: dir.appendingPathComponent("one.txt"), atomically: true, encoding: .utf8)
        let zip = dir.appendingPathComponent("fixture.zip")
        try run("/usr/bin/zip", [zip.path, "one.txt"], cwd: dir)

        let app = launchApp(arguments: ["-ArchivePath", zip.path])
        XCTAssertTrue(app.staticTexts["one.txt"].waitForExistence(timeout: 15), "archive did not load")

        // Spelled out rather than shared: a UI test drives the app as a black box
        // and links none of its code. The same string appears in
        // AccessibilityIdentifier.searchField and in sandboxpilot.json.
        let search = app.windows.searchFields["archive.searchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 10),
                      "the toolbar search field does not publish archive.searchField")
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

    /// The drop window's whole point: drag files out of Finder onto the floating
    /// window and an archive appears next to them, with no further questions.
    ///
    /// `-DropWindow 1` launches straight into it, so the panel is the only window
    /// and the drag has nothing else to land on. The fixture folder is outside
    /// the app's sandbox, so writing there needs the folder-access panel — which
    /// is exactly what a real first drop from a new folder looks like.
    func testDropWindowCompressesDroppedFile() throws {
        let dir = try makeWorkDir("dropwindow")
        defer { try? FileManager.default.removeItem(at: dir) }
        try "dropped".write(to: dir.appendingPathComponent("dropped.txt"), atomically: true, encoding: .utf8)

        let app = launchApp(arguments: ["-DropWindow", "1"])
        // by identifier, not by window title: the window is titled after the app,
        // exactly like the archive windows
        let dropArea = app.descendants(matching: .any)["quickCompress.dropArea"].firstMatch
        XCTAssertTrue(dropArea.waitForExistence(timeout: 15), "the drop window did not open")

        NSWorkspace.shared.open(dir)
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        let source = finder.textFields.matching(NSPredicate(format: "value == %@", "dropped.txt")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 15), "Finder does not show the file to drag")

        let target = dropArea.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1, thenDragTo: target)

        confirmAccessPanel(app, button: "Grant Access")

        let zip = dir.appendingPathComponent("dropped.zip")
        let deadline = Date().addingTimeInterval(30)
        while !FileManager.default.fileExists(atPath: zip.path), Date() < deadline {
            usleep(200_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: zip.path),
                      "the drop did not produce dropped.zip next to the source file")
        XCTAssertEqual(try zipEntries(zip), ["dropped.txt"])
        app.terminate()
    }

    /// Quick Compress offers every option the save panel does, in the window
    /// itself: opening the options shows them and widens the window.
    func testQuickCompressOffersEveryOption() throws {
        let app = launchApp(arguments: ["-DropWindow", "1", "-dropWindowOptionsExpanded", "NO"])
        let dropArea = app.descendants(matching: .any)["quickCompress.dropArea"].firstMatch
        XCTAssertTrue(dropArea.waitForExistence(timeout: 15), "the drop window did not open")
        let narrow = app.windows.firstMatch.frame.width

        app.buttons.matching(NSPredicate(format: "label == %@", "Options")).firstMatch.click()

        let password = app.secureTextFields["saveOptions.password"].firstMatch
        XCTAssertTrue(password.waitForExistence(timeout: 10), "the options do not show the password field")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "saveOptions.volume").firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "saveOptions.excludeDSStore").firstMatch.exists)
        XCTAssertGreaterThan(app.windows.firstMatch.frame.width, narrow, "the window did not widen for the options")
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

    // MARK: - Quick Look preview

    /// The Quick Look preview UI, driven through the debug harness
    /// (`-QuickLookPreview`), which hosts the very controller the extension runs.
    private func launchPreview(of archive: URL) -> XCUIApplication {
        launchApp(arguments: ["-QuickLookPreview", archive.path])
    }

    /// Clicks the disclosure triangle of the row showing `name`. The triangle
    /// sits left of the label and is not part of it, so it's reached by offset.
    private func expandRow(_ app: XCUIApplication, _ name: String) {
        app.staticTexts[name].firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: -26, dy: 0))
            .click()
    }

    /// A nested archive is browsable in the preview: its row offers a disclosure
    /// triangle before anything is known about the contents, and opening it
    /// unpacks the archive and lists what is inside.
    func testQuickLookPreviewOpensNestedArchive() throws {
        let dir = try makeWorkDir("ql-nested")
        defer { try? FileManager.default.removeItem(at: dir) }
        try "inner".write(to: dir.appendingPathComponent("inner.txt"), atomically: true, encoding: .utf8)
        try run("/usr/bin/zip", [dir.appendingPathComponent("inner.zip").path, "inner.txt"], cwd: dir)
        let outer = dir.appendingPathComponent("outer.zip")
        try run("/usr/bin/zip", [outer.path, "inner.zip"], cwd: dir)

        let app = launchPreview(of: outer)
        XCTAssertTrue(app.staticTexts["inner.zip"].waitForExistence(timeout: 15), "preview did not load")
        XCTAssertFalse(app.staticTexts["inner.txt"].exists, "nested contents were listed before the archive was opened")

        expandRow(app, "inner.zip")
        XCTAssertTrue(app.staticTexts["inner.txt"].waitForExistence(timeout: 20),
                      "the nested archive did not open")
        app.terminate()
    }

    /// Reading a nested archive means unpacking it first, so an encrypted outer
    /// archive needs its password — which the preview can neither take nor pass
    /// on. Finder's Quick Look panel keeps key focus, so a text field there never
    /// sees a keystroke, and the extension's sandbox denies it the LaunchServices
    /// call that would hand the archive to the app. All it can do is say so.
    ///
    /// The zip *listing* needs no password (only 7z `-mhe`/rar `-hp` headers do,
    /// and neither tool is guaranteed on a CI runner), which is why the notice is
    /// triggered here by opening the nested archive.
    func testQuickLookPreviewSaysWhenAnArchiveIsLocked() throws {
        let dir = try makeWorkDir("ql-password")
        defer { try? FileManager.default.removeItem(at: dir) }
        try "inner".write(to: dir.appendingPathComponent("inner.txt"), atomically: true, encoding: .utf8)
        try run("/usr/bin/zip", [dir.appendingPathComponent("inner.zip").path, "inner.txt"], cwd: dir)
        let outer = dir.appendingPathComponent("outer.zip")
        try run("/usr/bin/zip", ["-P", "password", outer.path, "inner.zip"], cwd: dir)

        let app = launchPreview(of: outer)
        XCTAssertTrue(app.staticTexts["inner.zip"].waitForExistence(timeout: 15), "preview did not load")

        expandRow(app, "inner.zip")

        let notice = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS %@", "password protected")).firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 20),
                      "no locked-archive notice for the encrypted archive")
        XCTAssertEqual(app.secureTextFields.count, 0,
                       "a password field cannot be typed into inside the Quick Look panel")
        XCTAssertFalse(app.buttons["Open in MacPacker"].firstMatch.exists,
                       "the extension cannot launch the app, so it must not offer to")
        app.terminate()
    }
    /// The save panel's "Options…" opens a sheet **on the panel itself**.
    ///
    /// This is the load-bearing assertion for the whole save-options design:
    /// under the App Sandbox the save panel is a Powerbox window hosted out of
    /// process, and our accessory view is a remote view inside it. If AppKit
    /// refuses the sheet there, the options have to move into a dialog shown
    /// before the panel instead.
    func testSaveOptionsSheetOpensOverSavePanel() throws {
        let dir = try makeWorkDir("saveoptions")
        defer { try? FileManager.default.removeItem(at: dir) }
        try "one".write(to: dir.appendingPathComponent("one.txt"), atomically: true, encoding: .utf8)
        let zip = dir.appendingPathComponent("fixture.zip")
        try run("/usr/bin/zip", [zip.path, "one.txt"], cwd: dir)

        let app = launchApp(arguments: ["-ArchivePath", zip.path])
        XCTAssertTrue(app.staticTexts["one.txt"].waitForExistence(timeout: 15), "archive did not load")

        // ⌘⇧S — Save As, which is what shows the panel with the accessory
        app.typeKey("s", modifierFlags: [.command, .shift])

        // the accessory is ours, hosted inside the panel — finding it at all is
        // half the question this test answers
        let optionsButton = app.buttons["saveOptionsButton"].firstMatch
        XCTAssertTrue(optionsButton.waitForExistence(timeout: 15),
                      "the save panel accessory never showed up")

        optionsButton.click()

        let done = app.buttons["saveOptionsDoneButton"].firstMatch
        let sheetAppeared = done.waitForExistence(timeout: 10)
        add(screenshot(app, name: "save-options-sheet"))
        XCTAssertTrue(sheetAppeared, "no options sheet over the save panel")

        // and it has to be interactive, not just present
        done.click()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), "the options sheet did not close")

        app.typeKey(.escape, modifierFlags: [])
        app.terminate()
    }

    /// A password typed twice differently never reaches the archive: the sheet
    /// says so and does not close until the two match.
    func testMismatchedPasswordsKeepTheOptionsOpen() throws {
        let (app, dir) = try openSaveAs("mismatch")
        defer { try? FileManager.default.removeItem(at: dir) }
        app.buttons["saveOptionsButton"].firstMatch.click()

        let password = app.secureTextFields["saveOptions.password"].firstMatch
        let verify = app.secureTextFields["saveOptions.passwordVerify"].firstMatch
        XCTAssertTrue(password.waitForExistence(timeout: 10), "no options sheet")
        password.click()
        password.typeText("secret")
        verify.click()
        verify.typeText("secreT")

        let done = app.buttons["saveOptionsDoneButton"].firstMatch
        XCTAssertTrue(app.staticTexts["saveOptions.problem"].firstMatch.waitForExistence(timeout: 5),
                      "no message for the mismatch")
        XCTAssertFalse(done.isEnabled, "Done must not close the sheet on a mismatch")

        verify.click()
        verify.typeKey("a", modifierFlags: .command)
        verify.typeText("secret")
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: done)], timeout: 5)
        done.click()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), "the options sheet did not close")

        app.typeKey(.escape, modifierFlags: [])
        app.terminate()
    }

    /// The whole way: 7z picked in the panel, a password with hidden names set in
    /// the sheet, Save. On disk is a 7z that 7-Zip cannot list without the
    /// password, and the window reopens it without asking for it again.
    func testSevenZWithPasswordWritesAnEncryptedArchive() throws {
        let (app, dir) = try openSaveAs("sevenz-password")
        defer { try? FileManager.default.removeItem(at: dir) }

        choose("7z", in: "saveFormatPicker", app)
        app.buttons["saveOptionsButton"].firstMatch.click()
        let password = app.secureTextFields["saveOptions.password"].firstMatch
        XCTAssertTrue(password.waitForExistence(timeout: 10), "no options sheet")
        password.click()
        password.typeText("secret")
        let verify = app.secureTextFields["saveOptions.passwordVerify"].firstMatch
        verify.click()
        verify.typeText("secret")
        let names = app.descendants(matching: .any).matching(identifier: "saveOptions.encryptNames").firstMatch
        XCTAssertTrue(names.exists, "7z offers to encrypt the names")
        if !isOn(names) { names.click() }
        app.buttons["saveOptionsDoneButton"].firstMatch.click()

        confirmSave(app)
        confirmAccessPanel(app, button: "Grant Access", timeout: 3)
        let saved = dir.appendingPathComponent("fixture.7z")
        XCTAssertTrue(waitForFile(saved), "fixture.7z was not written")

        XCTAssertTrue(app.staticTexts["one.txt"].waitForExistence(timeout: 15), "the saved archive did not reopen")
        XCTAssertEqual(app.secureTextFields.count, 0, "the window asked for the password it was just given")

        let bytes = try Data(contentsOf: saved)
        XCTAssertEqual(Array(bytes.prefix(6)), [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C], "not a 7z")
        let sevenZip = "/opt/homebrew/bin/7zz"
        if FileManager.default.isExecutableFile(atPath: sevenZip) {
            XCTAssertNotEqual(status(sevenZip, ["l", "-pwrong", saved.path]), 0, "7-Zip listed the names without the password")
            XCTAssertEqual(status(sevenZip, ["t", "-psecret", saved.path]), 0, "7-Zip could not test it with the password")
        }
        app.terminate()
    }

    /// The panel remembers per format and across launches, as 7-Zip does: 7z at
    /// Fastest with .DS_Store left out, saved, app quit — the next Save As has
    /// them again once 7z is picked, and no password. Writes the debug app's
    /// own defaults, which is the point.
    func testSaveSettingsComeBackAfterRelaunch() throws {
        let (app, dir) = try openSaveAs("remember")
        defer { try? FileManager.default.removeItem(at: dir) }

        choose("7z", in: "saveFormatPicker", app)
        choose("Fastest", in: "saveLevelPicker", app)
        app.buttons["saveOptionsButton"].firstMatch.click()
        let exclude = app.descendants(matching: .any).matching(identifier: "saveOptions.excludeDSStore").firstMatch
        XCTAssertTrue(exclude.waitForExistence(timeout: 10), "no options sheet")
        if !isOn(exclude) { exclude.click() }
        app.buttons["saveOptionsDoneButton"].firstMatch.click()
        confirmSave(app)
        confirmAccessPanel(app, button: "Grant Access", timeout: 3)
        XCTAssertTrue(waitForFile(dir.appendingPathComponent("fixture.7z")), "fixture.7z was not written")
        app.terminate()

        let again = launchApp(arguments: ["-ArchivePath", dir.appendingPathComponent("fixture.zip").path])
        XCTAssertTrue(again.staticTexts["one.txt"].waitForExistence(timeout: 15), "archive did not load")
        again.typeKey("s", modifierFlags: [.command, .shift])
        let format = again.popUpButtons["saveFormatPicker"].firstMatch
        XCTAssertTrue(format.waitForExistence(timeout: 15), "the save panel accessory never showed up")
        XCTAssertEqual(format.value as? String, "zip", "Save As starts from the archive's own format")
        choose("7z", in: "saveFormatPicker", again)
        XCTAssertEqual(again.popUpButtons["saveLevelPicker"].firstMatch.value as? String, "Fastest",
                       "7z's level was not remembered")
        again.buttons["saveOptionsButton"].firstMatch.click()
        let excludeAgain = again.descendants(matching: .any).matching(identifier: "saveOptions.excludeDSStore").firstMatch
        XCTAssertTrue(excludeAgain.waitForExistence(timeout: 10), "no options sheet")
        XCTAssertTrue(isOn(excludeAgain), "the .DS_Store choice was not remembered")
        XCTAssertEqual((again.secureTextFields["saveOptions.password"].firstMatch.value as? String) ?? "", "",
                       "a password must never be remembered")
        again.buttons["saveOptionsDoneButton"].firstMatch.click()
        again.typeKey(.escape, modifierFlags: [])
        again.terminate()
    }

    /// A fresh fixture zip, opened, with the Save As panel up.
    private func openSaveAs(_ name: String) throws -> (XCUIApplication, URL) {
        let dir = try makeWorkDir(name)
        try "one".write(to: dir.appendingPathComponent("one.txt"), atomically: true, encoding: .utf8)
        let zip = dir.appendingPathComponent("fixture.zip")
        try run("/usr/bin/zip", [zip.path, "one.txt"], cwd: dir)

        let app = launchApp(arguments: ["-ArchivePath", zip.path])
        XCTAssertTrue(app.staticTexts["one.txt"].waitForExistence(timeout: 15), "archive did not load")
        app.typeKey("s", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.buttons["saveOptionsButton"].firstMatch.waitForExistence(timeout: 15),
                      "the save panel accessory never showed up")
        return (app, dir)
    }

    /// Picks `item` from the popup with accessibility identifier `id`.
    private func choose(_ item: String, in id: String, _ app: XCUIApplication) {
        let popup = app.popUpButtons[id].firstMatch
        XCTAssertTrue(popup.waitForExistence(timeout: 5), "no \(id)")
        popup.click()
        app.menuItems[item].firstMatch.click()
    }

    private func isOn(_ toggle: XCUIElement) -> Bool {
        switch toggle.value {
        case let number as NSNumber: return number.boolValue
        case let text as String: return text == "1"
        default: return false
        }
    }

    /// The panel's Save button; Return when AppKit does not expose it by name.
    private func confirmSave(_ app: XCUIApplication) {
        let save = app.buttons["OKButton"].firstMatch
        if save.exists { save.click() } else { app.typeKey(.return, modifierFlags: []) }
    }

    private func waitForFile(_ url: URL, timeout: TimeInterval = 20) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !FileManager.default.fileExists(atPath: url.path) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Exit status of a tool whose verdict is the status alone.
    private func status(_ tool: String, _ args: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Screenshot attached to the report — the sandboxed panel is the one place
    /// where "the query found nothing" and "nothing was drawn" differ.
    private func screenshot(_ app: XCUIApplication, name: String) -> XCTAttachment {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        return shot
    }
}
