import XCTest

/// MAIN DEVELOPMENT CONFIGURATION — Profile › Devices & Connections (sheet P06) in the MAIN Cyclift app with the
/// redesign switched on by its simulator-only test setting, on a seeded test athlete (a hybrid athlete).
/// The connection states are GIVEN to the Devices page for display (`BC_UITEST_DEVICE_STATES`, simulator only);
/// nothing is connected, paired, scanned, recorded or written, and no action that would ask iOS for a permission is
/// pressed here (Add a sensor, the Apple Health switches, Start watch workout are required to EXIST, not pressed).
/// Every row, page and control named here is required: a missing one fails the test.
final class RedesignMainProfileTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["LAYOUT_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("redesign-main-profile-\(name).png"))
    }
    private func must(_ e: XCUIElement, _ what: String, timeout: TimeInterval = 10) { XCTAssertTrue(e.waitForExistence(timeout: timeout), "required: \(what)") }

    private func launchToDevices(_ states: String?) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_SEED_JSON"] = LaunchSmokeTests.build36Store()
        app.launchEnvironment["BC_UITEST_REDESIGN"] = "1"; app.launchEnvironment["BC_UITEST_THEME"] = "obsidian"
        if let states { app.launchEnvironment["BC_UITEST_DEVICE_STATES"] = states }
        app.launch()
        must(el(app, "homeV23"), "Home v2.3 in the main app", timeout: 40)
        XCTAssertFalse(el(app, "labThemeName").exists, "the main app carries no Cyclift Lab strip")
        let avatar = app.buttons["homeAvatar"].firstMatch; must(avatar, "the Home avatar"); avatar.tap()
        let d = el(app, "profileSectionD"); must(d, "Devices & Connections on the Profile landing"); d.tap()
        must(el(app, "profileDevice-watch"), "the Apple Watch row")
        return app
    }
    private func row(_ app: XCUIApplication, _ id: String) -> XCUIElement { el(app, "profileDevice-\(id)") }
    /// Opens a family row; its page's status line must be on screen and say `word`; every action named must exist.
    /// Leaves the page open for further checks; `back` returns to the row.
    private func open(_ app: XCUIApplication, _ id: String, says words: [String], actions: [String]) {
        let r = row(app, id); must(r, "the \(id) row")
        _ = app.reveal(r, top: 120, bottomMargin: 130); r.tap()
        let status = el(app, "deviceStatus-\(id)")
        must(status, "the \(id) page's status line")
        XCTAssertTrue(words.contains { status.label.contains($0) }, "required: the \(id) page shows the same state as its row, one of \(words) (\(status.label))")
        XCTAssertFalse(status.label.contains("Cyclift Lab"), "the main app's \(id) page is not the Lab page (\(status.label))")
        for a in actions {
            let e = el(app, a)
            if !e.exists { app.swipeUp() }
            must(e, "\(a) on the \(id) page", timeout: 5)
        }
        XCTAssertFalse(r.exists && r.isHittable, "required: the \(id) page is on top of its row")
    }
    private func back(_ app: XCUIApplication, to id: String) {
        XCTAssertTrue(app.backReveals(row(app, id)), "required: back from the \(id) page returns to its row")
    }

    /// Each family row's word from controlled states, each page behind it with its state and its actions, the
    /// "This iPhone" row and page, and Connection diagnostics.
    func testDevicePagesShowTheirStateAndActionsInTheRedesignedMainApp() {
        let app = launchToDevices("apple-health=connected;watch=receiving;bikecomputer=problem:Bluetooth is off")

        // the rows (sheet D), in the sheet's order
        for id in ["health", "watch", "board", "cywatch", "hr", "power", "other", "phone", "diagnostics"] { must(row(app, id), "device row \(id)") }
        XCTAssertTrue(row(app, "watch").label.contains("Receiving"), "required: a live watch reads Receiving (\(row(app, "watch").label))")
        let healthWords = ["Connected", "Unavailable"]      // Unavailable where the simulator has no Apple Health
        XCTAssertTrue(healthWords.contains { row(app, "health").label.contains($0) }, "required: Apple Health reads Connected, or Unavailable where the device has none (\(row(app, "health").label))")
        XCTAssertTrue(row(app, "board").label.contains("Unavailable"), "required: Bluetooth off reads Unavailable (\(row(app, "board").label))")
        XCTAssertTrue(row(app, "cywatch").label.contains("Unavailable"), "required: the future Cyclift Watch is never shown as working")
        for id in ["hr", "power", "other"] { XCTAssertTrue(row(app, id).label.contains("Not configured"), "required: with no sensor paired \(id) reads Not configured (\(row(app, id).label))") }
        let phone = row(app, "phone")
        XCTAssertTrue(phone.label.contains("This iPhone") && phone.label.contains("Bluetooth") && phone.label.contains("location"), "required: This iPhone states Bluetooth and location (\(phone.label))")
        XCTAssertFalse(phone.label.contains("Cyclift Lab"), "the main app's This iPhone row is not the Lab row")
        XCTAssertGreaterThan(row(app, "diagnostics").frame.minY, phone.frame.minY, "This iPhone sits above Connection diagnostics, as on the sheet")
        shot("d-rows")

        // Apple Health (sheet D3)
        open(app, "health", says: healthWords, actions: ["healthUse", "healthExportRides", "healthImport", "healthImportNow", "healthRead-weight", "healthRead-restingHR", "healthRead-hrv", "healthRead-sleep"])
        shot("d3-apple-health"); back(app, to: "health")

        // Apple Watch
        open(app, "watch", says: ["Receiving"], actions: ["watchUse", "watchPaired", "watchHR", "watchTest", "watchStart"])
        shot("d-apple-watch"); back(app, to: "watch")

        // Cyclift BikeComputer (sheet D1)
        open(app, "board", says: ["Unavailable"], actions: ["boardAutoConnect", "boardProfileSync", "boardSettings", "boardDiagnostics", "boardHelp", "boardPrimary"])
        shot("d1-bikecomputer")
        XCTAssertFalse(app.navigationBars["BikeComputer"].firstMatch.exists, "the redesigned page, not the existing BikeComputer list")
        let diag = el(app, "boardDiagnostics"); _ = app.reveal(diag, top: 120, bottomMargin: 130)
        XCTAssertTrue(app.tapPresents(diag, page: "diagStage"), "required: Connection diagnostics opens its redesigned page")
        must(el(app, "diagUsable"), "the link-usable line"); shot("d1-diagnostics")
        XCTAssertTrue(app.backReveals(diag), "required: back from Connection diagnostics")
        let help = el(app, "boardHelp")
        XCTAssertTrue(app.tapPresents(help, page: "devicePage-boardHelp") || app.staticTexts["Pairing help"].firstMatch.exists, "required: Pairing help opens")
        must(app.staticTexts["PAIRING STEPS"].firstMatch, "the pairing steps")
        XCTAssertTrue(app.backReveals(help), "required: back from Pairing help")
        // one row here still opens its existing page: profile sync (it can write the profile to the board)
        let syncRow = el(app, "boardProfileSync"); _ = app.reveal(syncRow, top: 120, bottomMargin: 130); syncRow.tap()
        must(app.navigationBars["Sync status"].firstMatch, "Profile sync opens the existing sync page")
        XCTAssertTrue(app.backReveals(syncRow), "required: back from the sync page")
        back(app, to: "board")

        // sensors (sheet D2): the three families use the same page
        for id in ["hr", "power", "other"] {
            open(app, id, says: ["Not configured"], actions: ["sensorAdd"])      // Add a sensor is NOT pressed: it would start a Bluetooth search
            if id == "hr" { shot("d2-sensors") }
            back(app, to: id)
        }

        // the future device opens nothing
        let cy = row(app, "cywatch"); _ = app.reveal(cy, top: 120, bottomMargin: 130); cy.tap()
        XCTAssertTrue(cy.exists && cy.isHittable, "required: Cyclift Watch opens nothing")

        // This iPhone
        _ = app.reveal(phone, top: 120, bottomMargin: 130); phone.tap()
        for id in ["phoneBluetooth", "phoneLocation", "phoneNotifications", "phoneOpenSettings"] { must(el(app, id), "\(id) on This iPhone") }
        let bt = el(app, "phoneBluetooth").label
        XCTAssertTrue(["On", "Off", "Not allowed", "Not available"].contains { bt.contains($0) }, "required: Bluetooth is stated in one of its words (\(bt))")
        let loc = el(app, "phoneLocation").label
        XCTAssertTrue(["Allowed", "Not allowed", "Not asked yet"].contains { loc.contains($0) }, "required: location is stated in one of its words (\(loc))")
        XCTAssertFalse(bt.contains("Cyclift Lab") || loc.contains("Cyclift Lab"), "the main app reads the real state")
        XCTAssertFalse(el(app, "phoneHealth").exists, "This iPhone lists Bluetooth, location and notifications; Health is on Permissions")
        shot("d-this-iphone")
        XCTAssertTrue(app.backReveals(phone), "required: back from This iPhone")

        // Connection diagnostics: the existing page, kept as it is
        let dg = row(app, "diagnostics"); _ = app.reveal(dg, top: 120, bottomMargin: 130); dg.tap()
        must(app.navigationBars["Diagnostics"].firstMatch, "Connection diagnostics opens the existing diagnostics page")
        XCTAssertTrue(app.backReveals(dg), "required: back from diagnostics")
        app.terminate()
    }

    /// A lost link and a remembered-but-idle board: the words on the rows and on their pages.
    func testALostLinkAndAPairedBoardReadTheSameOnTheirPages() {
        let app = launchToDevices("watch=problem:Out of range;bikecomputer=paired")
        XCTAssertTrue(row(app, "watch").label.contains("Disconnected"), "required: a lost link reads Disconnected (\(row(app, "watch").label))")
        XCTAssertTrue(row(app, "board").label.contains("Paired"), "required: a remembered board reads Paired (\(row(app, "board").label))")
        open(app, "watch", says: ["Disconnected"], actions: ["watchUse", "watchTest"])
        shot("d-apple-watch-disconnected"); back(app, to: "watch")
        open(app, "board", says: ["Paired"], actions: ["boardAutoConnect", "boardPrimary"])
        shot("d1-bikecomputer-paired"); back(app, to: "board")
        app.terminate()
    }

    /// Data, Help & About › Permissions in the main app: the four lines in real words and the way to iPhone Settings.
    func testPermissionsPageStatesTheRealPermissions() {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_SEED_JSON"] = LaunchSmokeTests.build36Store()
        app.launchEnvironment["BC_UITEST_REDESIGN"] = "1"; app.launchEnvironment["BC_UITEST_THEME"] = "obsidian"
        app.launch()
        must(el(app, "homeV23"), "Home v2.3 in the main app", timeout: 40)
        let avatar = app.buttons["homeAvatar"].firstMatch; must(avatar, "the Home avatar"); avatar.tap()
        let f = el(app, "profileSectionF"); must(f, "Data, Help & About"); _ = app.reveal(f, top: 120, bottomMargin: 130); f.tap()
        let p = el(app, "profilePermissions"); must(p, "Permissions row")
        XCTAssertFalse(p.label.contains("Not available"), "Permissions is no longer a stated limit (\(p.label))")
        p.tap()
        for id in ["phoneBluetooth", "phoneLocation", "phoneHealth", "phoneNotifications", "phoneOpenSettings"] { must(el(app, id), "\(id) on Permissions") }
        let n = el(app, "phoneNotifications").label
        XCTAssertTrue(["Allowed", "Not allowed", "Not asked yet", "Checking"].contains { n.contains($0) }, "required: notifications are stated in one of their words (\(n))")
        shot("f2-permissions")
        XCTAssertTrue(app.backReveals(p), "required: back from Permissions")
        for id in ["profileDiagnostics", "profileHelp", "profileSettings", "profileExport"] { must(el(app, id), "\(id) on Data, Help & About") }
    }
}
