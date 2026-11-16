import XCTest

/// Cyclift Lab only (ios/project-lab.yml). Drives the built Lab app with its own generated demo athlete — no seed, no
/// reset hook — and keeps screenshots when the runner sets LAYOUT_DIR.
final class LabChecks: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }

    private var outDir: String? { let v = ProcessInfo.processInfo.environment["LAYOUT_DIR"] ?? ""; return v.isEmpty ? nil : v }
    private func shot(_ name: String) {
        guard let dir = outDir else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("lab-\(name).png"))
    }
    private func banner(_ app: XCUIApplication) -> Bool { app.staticTexts["CYCLIFT LAB · DEMO DATA"].firstMatch.waitForExistence(timeout: 10) }
    private func tab(_ app: XCUIApplication, _ name: String) {
        let b = app.buttons[name].firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: 8), "tab \(name)")
        if b.exists { b.tap(); app.settleForScreenshot(2) }
    }
    /// Lab 3 and 4: the chooser was not found by its identifier (an identifier on the banner row replaced it; that one is
    /// removed). It is now found by identifier or by what it says, whichever iOS exposes.
    private func chooser(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'labThemeMenu' OR label BEGINSWITH 'Theme' OR label BEGINSWITH 'Close and reopen'")).firstMatch
    }
    private let themes: [(id: String, title: String)] = [("obsidian", "Obsidian"), ("arctic", "Arctic"), ("ocean", "Ocean"), ("forest", "Forest"), ("sandstone", "Sandstone"), ("highContrast", "High Contrast")]

    /// The same five screens in each theme, each from a fresh launch in that theme.
    func test1FiveScreensInSixThemes() {
        for (i, t) in themes.enumerated() {
            let app = XCUIApplication()
            app.launchEnvironment["LAB_THEME"] = t.id
            app.launch()
            XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30), "\(t.id): Home with the demo athlete")
            XCTAssertTrue(banner(app), "\(t.id): the demo banner is shown")
            let tag = "\(i + 1)-\(t.id)"
            app.settleForScreenshot(2); shot("\(tag)-1-home")
            let coach = app.buttons["homeCoachAction"].firstMatch
            if coach.exists { XCTAssertTrue(coach.label.hasPrefix("Demo, rule-based, not AI."), "\(t.id): the Coach card says it is demo and not AI (\(coach.label))") }
            app.swipeUp(); app.settleForScreenshot(); shot("\(tag)-2-home-lower")
            let centre = app.buttons["centreButton"].firstMatch
            if centre.waitForExistence(timeout: 5) { centre.tap(); app.settleForScreenshot(2); shot("\(tag)-3-train"); XCTAssertTrue(banner(app), "\(t.id): banner on Train") }
            tab(app, "Plan"); shot("\(tag)-4-plan")
            tab(app, "Progress"); shot("\(tag)-5-progress")
            tab(app, "Profile"); shot("\(tag)-6-profile"); XCTAssertTrue(banner(app), "\(t.id): banner on Profile")
            app.terminate()
        }
    }

    /// Choosing a theme in the banner changes the screen at once: no relaunch, and the picture really changes.
    func test2ThemesSwitchWithoutRelaunch() {
        let app = XCUIApplication()
        app.launchEnvironment["LAB_THEME"] = "obsidian"
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30))
        var last = XCUIScreen.main.screenshot().pngRepresentation
        for i in Array(1..<themes.count) + [0] {      // every other theme, then back to the first
            let t = themes[i]
            // Lab 3: the chooser is not exposed as a Button, so it is looked up by its identifier whatever its type
            let menu = chooser(app)
            XCTAssertTrue(menu.waitForExistence(timeout: 8), "theme chooser"); menu.tap()
            let choice = app.buttons[t.title].firstMatch
            XCTAssertTrue(choice.waitForExistence(timeout: 5), "choice \(t.title)"); choice.tap()
            app.settleForScreenshot(2)
            XCTAssertEqual(app.state, .runningForeground, "\(t.id): still the same running app")
            XCTAssertTrue(chooser(app).label.contains(t.title), "\(t.id): the chooser names the theme now shown (\(chooser(app).label))")
            XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 10), "\(t.id): Home is shown after the change")
            let now = XCUIScreen.main.screenshot().pngRepresentation
            XCTAssertNotEqual(now, last, "\(t.id): the screen did not change")
            last = now; shot("switch-\(i + 1)-\(t.id)")
        }
    }

    /// Delete all data inside Lab: back to Welcome at once, still empty after a plain relaunch, banner still there.
    /// (That the production app's files are untouched is checked outside, by ios/ci/lab.sh.) Runs last.
    func test3DeleteAllDataEmptiesLabAndStaysEmpty() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30))
        tab(app, "Profile")
        let settings = app.buttons["profileSettings"].firstMatch
        var tries = 0
        while !(settings.exists && settings.isHittable) && tries < 10 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "Profile › Settings"); settings.tap()
        let delete = app.buttons["deleteAllData"].firstMatch
        tries = 0
        while !(delete.exists && delete.isHittable) && tries < 12 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(delete.waitForExistence(timeout: 10), "Delete all data"); delete.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "deletion asks first"); shot("delete-1-question")
        alert.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.buttons["onboardingContinue"].firstMatch.waitForExistence(timeout: 15), "after Delete, Lab is at Welcome")
        XCTAssertTrue(banner(app), "the demo banner stays on Welcome"); shot("delete-2-welcome")
        app.terminate()
        let again = XCUIApplication()
        again.launch()
        XCTAssertTrue(again.buttons["onboardingContinue"].firstMatch.waitForExistence(timeout: 30), "relaunch: still Welcome, the demo athlete did not come back")
        XCTAssertFalse(again.waitForHome(name: "Demo", timeout: 3), "the deleted demo athlete must not reappear")
        shot("delete-3-relaunch")
    }

    /// After the deletion above Lab is empty. "Restore the demo athlete" is an explicit choice: nothing comes back until
    /// it is chosen AND Lab is reopened; then the demo athlete is there again.
    func test4RestoreBringsTheDemoAthleteBackOnlyWhenAsked() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["onboardingContinue"].firstMatch.waitForExistence(timeout: 30), "starts empty (after the deletion test)")
        let menu = chooser(app)
        XCTAssertTrue(menu.waitForExistence(timeout: 8), "banner menu"); menu.tap()
        let restore = app.buttons["Restore the demo athlete"].firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 5), "the restore choice"); restore.tap()
        app.settleForScreenshot(1)
        XCTAssertTrue(app.buttons["onboardingContinue"].firstMatch.exists, "nothing changes until Lab is reopened")
        shot("restore-1-asked")
        app.terminate()
        let again = XCUIApplication()
        again.launch()
        XCTAssertTrue(again.waitForHome(name: "Demo", timeout: 30), "after reopening, the demo athlete is back")
        shot("restore-2-back")
    }
}
