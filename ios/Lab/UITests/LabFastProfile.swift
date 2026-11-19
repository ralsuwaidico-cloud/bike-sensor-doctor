import XCTest

/// Cyclift Lab — Profile v2.0 button map (sheet P09b), fast check. One launch per section. Every row of every Profile
/// section is opened and the DESTINATION'S OWN control or title must be on screen (not merely "some text exists"),
/// then the check comes back and the row must be reachable again. Rows that state a limit and open nothing are
/// required to say so. Each page behind Devices & Connections (sheet P06) is photographed in its Lab state: nothing
/// connects, nothing is asked. A missing row or a row that leads nowhere FAILS the check.
final class LabFastProfile: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["LAYOUT_DIR"] ?? ""
        guard !dir.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("fast-\(name).png"))
    }
    private func launch(_ extra: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LAB_FRESH_DEMO"] = "1"
        app.launchEnvironment["LAB_THEME"] = "obsidian"
        for (k, v) in extra { app.launchEnvironment[k] = v }
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30), "required: Home with the demo athlete")
        return app
    }
    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func openSection(_ app: XCUIApplication, _ id: String) {
        let avatar = app.buttons["homeAvatar"].firstMatch
        XCTAssertTrue(avatar.waitForExistence(timeout: 8), "required: the Home avatar"); avatar.tap()
        let s = el(app, id)
        XCTAssertTrue(s.waitForExistence(timeout: 8), "required: \(id) on the Profile landing")
        _ = app.reveal(s, top: 120, bottomMargin: 130); s.tap()
    }

    /// What proves a destination is the one shown.
    private enum Proof {
        case id(String)            // an element with this identifier, belonging to the destination
        case bar(String)           // the destination's navigation-bar title (existing pages)
        case title(String)         // the destination's large title text (redesigned pages)
    }
    private func proofElement(_ app: XCUIApplication, _ p: Proof) -> XCUIElement {
        switch p {
        case .id(let i): return el(app, i)
        case .bar(let t): return app.navigationBars[t].firstMatch
        case .title(let t): return app.staticTexts[t].firstMatch
        }
    }
    /// Taps the row; the destination's own proof must be on screen, the back button usable and the row no longer
    /// reachable underneath. Then goes back; the row must be reachable again.
    private func opens(_ app: XCUIApplication, _ rowId: String, _ proof: Proof, shotName: String? = nil) {
        let row = el(app, rowId)
        XCTAssertTrue(row.waitForExistence(timeout: 8), "required: row \(rowId)")
        guard row.exists else { return }
        _ = app.reveal(row, top: 120, bottomMargin: 130)
        row.tap()
        let dest = proofElement(app, proof)
        let shown = dest.waitForExistence(timeout: 8)
        XCTAssertTrue(shown, "required: \(rowId) opens its own page (\(proof))")
        if shown { XCTAssertTrue(!dest.frame.isEmpty && app.frame.intersects(dest.frame), "required: the page behind \(rowId) is on screen") }
        XCTAssertFalse(row.exists && row.isHittable, "required: \(rowId) is not still on top after its page opened")
        if let shotName { app.settleForScreenshot(1); shot(shotName) }
        guard shown else { return }
        XCTAssertTrue(app.backReveals(row), "required: back from the page behind \(rowId) returns to its row")
    }
    /// A row that states a limit: it must exist, say so, and open nothing.
    private func statesLimit(_ app: XCUIApplication, _ rowId: String, contains word: String) {
        let row = el(app, rowId)
        XCTAssertTrue(row.waitForExistence(timeout: 8), "required: row \(rowId)")
        guard row.exists else { return }
        _ = app.reveal(row, top: 120, bottomMargin: 130)
        XCTAssertTrue(row.label.contains(word), "required: \(rowId) says \"\(word)\" (\(row.label))")
        opensNothing(app, row, rowId)
    }

    /// Tapping it changes nothing: the row is still there, on top, and no page was pushed over it.
    private func opensNothing(_ app: XCUIApplication, _ row: XCUIElement, _ rowId: String) {
        guard row.isHittable else { XCTFail("required: \(rowId) is on screen"); return }
        row.tap()
        app.settleForScreenshot(1)
        XCTAssertTrue(row.exists && row.isHittable, "required: \(rowId) opens nothing")
    }

    /// Sheet P03 — Athlete Profile.
    func testAthleteProfileRows() {
        let app = launch()
        openSection(app, "profileSectionA")
        opens(app, "profilePersonal", .id("personalName"))
        statesLimit(app, "profileActivities", contains: "Not available")
        opens(app, "profileType", .id("typeMode"))
        opens(app, "profileExperience", .id("typeRiding"))
        opens(app, "profileBalance", .id("typeBalance"))        // the demo athlete is a hybrid athlete
        shot("p09b-A-athlete-profile")
    }

    /// Sheet P04 — Training Setup. The Plan- and Train-owned rows open the pages that own them.
    func testTrainingSetupRows() {
        let app = launch()
        openSection(app, "profileSectionB")
        opens(app, "profileEquipment", .id("equipExcluded"))
        opens(app, "profilePreferences", .id("otherSports"))
        opens(app, "profileHealthSafety", .id("recoveryCapacity"))
        opens(app, "profileGoal", .bar("Goals"))
        opens(app, "profileWeek", .bar("Your week"))
        opens(app, "profileRoutines", .bar("Routines"))
        opens(app, "profileExercises", .bar("My exercises"))
        shot("p09b-B-training-setup")
    }

    /// Sheet P05 — Performance Settings.
    func testPerformanceRows() {
        let app = launch()
        openSection(app, "profileSectionC")
        opens(app, "profileHR", .id("hrResting"))
        opens(app, "profileFTP", .id("ftpValue"))
        opens(app, "profileCadence", .id("cadenceLow"))
        opens(app, "profileCycling", .id("wheelMm"))
        opens(app, "profileSources", .id("hrSource"))
        shot("p09b-C-performance")
    }

    /// Sheet P06 — Devices & Connections in Lab: every family reads Unavailable, "This iPhone" says Bluetooth and
    /// location are not used, and each page behind a row says the same and offers no action. A picture of each page.
    func testDevicesRowsAndPagesInLab() {
        let app = launch()
        openSection(app, "profileSectionD")
        let families = ["health", "watch", "board", "hr", "power", "other"]
        for f in families + ["cywatch"] {
            let row = el(app, "profileDevice-\(f)")
            XCTAssertTrue(row.waitForExistence(timeout: 8), "required: device row \(f)")
            XCTAssertTrue(row.label.contains("Unavailable"), "required: in Lab \(f) reads Unavailable (\(row.label))")
            for word in ["Connected", "Receiving", "Paired"] { XCTAssertFalse(row.label.contains(word), "in Lab \(f) never reads \(word) (\(row.label))") }
        }
        let phone = el(app, "profileDevice-phone")
        XCTAssertTrue(phone.waitForExistence(timeout: 8), "required: the This iPhone row")
        XCTAssertTrue(phone.label.contains("This iPhone") && phone.label.contains("not used in Cyclift Lab"), "required: This iPhone says nothing is used in Lab (\(phone.label))")
        shot("p06-D-devices-lab")

        for f in families {
            let row = el(app, "profileDevice-\(f)")
            _ = app.reveal(row, top: 120, bottomMargin: 130); row.tap()
            let status = el(app, "deviceStatus-\(f)")
            XCTAssertTrue(status.waitForExistence(timeout: 8), "required: \(f) opens its page with a status line")
            XCTAssertTrue(status.label.contains("Unavailable") && status.label.contains("Not used in Cyclift Lab"), "required: the \(f) page says it is not used in Lab (\(status.label))")
            XCTAssertTrue(el(app, "deviceLabNote-\(f)").exists, "required: the \(f) page says Lab connects to nothing")
            // no action is offered in Lab
            for action in ["boardPrimary", "boardRepair", "boardForget", "sensorAdd", "healthUse", "healthImportNow", "watchStart", "watchTest", "phoneOpenSettings"] {
                XCTAssertFalse(el(app, action).exists, "in Lab the \(f) page offers no \(action)")
            }
            app.settleForScreenshot(1); shot("p06-page-\(f)-lab")
            XCTAssertTrue(app.backReveals(row), "required: back from the \(f) page")
        }
        // the future device opens nothing
        let cy = el(app, "profileDevice-cywatch")
        _ = app.reveal(cy, top: 120, bottomMargin: 130)
        opensNothing(app, cy, "profileDevice-cywatch")
        // This iPhone
        _ = app.reveal(phone, top: 120, bottomMargin: 130); phone.tap()
        for id in ["phoneBluetooth", "phoneLocation", "phoneNotifications"] {
            let fact = el(app, id)
            XCTAssertTrue(fact.waitForExistence(timeout: 8), "required: \(id) on This iPhone")
            XCTAssertTrue(fact.label.contains("Not used in Cyclift Lab"), "required: \(id) is not used in Lab (\(fact.label))")
        }
        XCTAssertFalse(el(app, "phoneOpenSettings").exists, "Lab offers no permission action")
        app.settleForScreenshot(1); shot("p06-page-phone-lab")
        XCTAssertTrue(app.backReveals(phone), "required: back from This iPhone")
        // nothing asked the system for anything: no permission alert is on screen
        XCTAssertEqual(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.count, 0, "Lab raised no system permission question")
    }

    /// Sheet P07 — App Preferences.
    func testAppPreferencesRows() {
        let app = launch()
        openSection(app, "profileSectionE")
        opens(app, "profileAppearance", .id("theme-system"))
        let language = el(app, "profileLanguage")
        XCTAssertTrue(language.waitForExistence(timeout: 8) && language.label.contains("English"), "required: Language states English")
        statesLimit(app, "profileArabic", contains: "Not available")
        opens(app, "profileUnits", .id("unitsChoice"))
        opens(app, "profileNotifications", .id("settingsNotifications"))
        opens(app, "profileCoach", .id("coachDuringRides"))
        opens(app, "profileDisplay", .id("keepScreenOn"))
        opens(app, "profileAccessibility", .title("Notifications & display"))
        shot("p09b-E-app-preferences")
    }

    /// Sheet P08 — Data, Help & About. Export and Delete are only confirmed to reach their existing protected
    /// controls; nothing is exported or deleted here.
    func testDataHelpAboutRows() {
        let app = launch()
        openSection(app, "profileSectionF")
        opens(app, "profileDataWhere", .id("profileBackup"))
        opens(app, "profileExport", .id("exportData"))
        opens(app, "profilePermissions", .id("phoneHealth"), shotName: "p08-F2-permissions-lab")
        opens(app, "profileSettings", .bar("Settings"))
        opens(app, "profileHelp", .bar("Help & support"))
        opens(app, "profileDiagnostics", .bar("Diagnostics"))
        opens(app, "profilePrivacy", .bar("Privacy policy"))
        opens(app, "profileTerms", .bar("Terms of use"))
        let version = el(app, "profileVersion")
        _ = app.reveal(version, top: 120, bottomMargin: 130)
        XCTAssertTrue(version.exists && version.label.contains("Cyclift"), "required: the version row")
        shot("p09b-F-data-help-about")
    }

    /// Permissions in Lab: every line says it is not used; no button leads to iPhone Settings.
    func testPermissionsPageInLabAsksForNothing() {
        let app = launch()
        openSection(app, "profileSectionF")
        let row = el(app, "profilePermissions")
        XCTAssertTrue(row.waitForExistence(timeout: 8), "required: Permissions row"); row.tap()
        for id in ["phoneBluetooth", "phoneLocation", "phoneHealth", "phoneNotifications"] {
            let fact = el(app, id)
            XCTAssertTrue(fact.waitForExistence(timeout: 8), "required: \(id)")
            XCTAssertTrue(fact.label.contains("Not used in Cyclift Lab"), "required: \(id) is not used in Lab (\(fact.label))")
        }
        XCTAssertFalse(el(app, "phoneOpenSettings").exists, "Lab offers no permission action")
    }

    /// Large text (the largest ordinary iPhone text size): the Profile landing and the Devices page still show every
    /// row, and neighbouring rows do not run into each other.
    func testProfileRowsDoNotOverlapAtLargeText() {
        let app = XCUIApplication()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"]
        app.launchEnvironment["LAB_FRESH_DEMO"] = "1"
        app.launchEnvironment["LAB_THEME"] = "obsidian"
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30), "required: Home with the demo athlete")
        let avatar = app.buttons["homeAvatar"].firstMatch
        XCTAssertTrue(avatar.waitForExistence(timeout: 8), "required: the Home avatar"); avatar.tap()
        let sections = ["profileSectionA", "profileSectionB", "profileSectionC", "profileSectionD", "profileSectionE", "profileSectionF"]
        XCTAssertTrue(el(app, sections[0]).waitForExistence(timeout: 8), "required: the Profile landing")
        shot("p10-landing-large-text")
        separate(app, sections, "landing")
        let d = el(app, "profileSectionD"); _ = app.reveal(d, top: 120, bottomMargin: 130); d.tap()
        XCTAssertTrue(el(app, "profileDevice-health").waitForExistence(timeout: 8), "required: Devices at large text")
        shot("p10-devices-large-text")
        separate(app, ["health", "watch", "board", "cywatch", "hr", "power", "other", "phone"].map { "profileDevice-\($0)" }, "devices")
    }
    /// Each pair of neighbouring rows: the upper one ends before the lower one begins (measured in the same scroll position).
    private func separate(_ app: XCUIApplication, _ ids: [String], _ tag: String) {
        for (a, b) in zip(ids, ids.dropFirst()) {
            let lower = el(app, b), upper = el(app, a)
            XCTAssertTrue(lower.waitForExistence(timeout: 8) && upper.exists, "required (\(tag), large text): rows \(a) and \(b)")
            _ = app.reveal(lower, top: 120, bottomMargin: 130)
            guard upper.exists, lower.exists else { continue }
            XCTAssertLessThanOrEqual(upper.frame.maxY, lower.frame.minY + 1, "required (\(tag), large text): \(a) does not run into \(b)")
        }
    }
}
