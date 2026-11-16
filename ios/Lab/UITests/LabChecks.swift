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
    /// The strip's theme name ("Theme: Ocean").
    private func themeName(_ app: XCUIApplication) -> String { app.staticTexts["labThemeName"].firstMatch.label }
    /// Navigation v1.2 / Profile v2.0: Profile has no tab; the Home avatar opens the one Profile.
    private func openProfile(_ app: XCUIApplication) -> Bool {
        tab(app, "Home")
        let avatar = app.buttons["homeAvatar"].firstMatch
        guard avatar.waitForExistence(timeout: 8) else { return false }
        avatar.tap(); app.settleForScreenshot(2)
        return app.descendants(matching: .any).matching(identifier: "profileSectionA").firstMatch.waitForExistence(timeout: 8)
    }
    /// Profile → Data, Help & About → the existing settings page (export, permissions, delete all data).
    private func openSettings(_ app: XCUIApplication) -> Bool {
        let f = app.descendants(matching: .any).matching(identifier: "profileSectionF").firstMatch
        var tries = 0
        while !(f.exists && f.isHittable) && tries < 6 { app.swipeUp(); tries += 1 }
        guard f.exists else { return false }
        f.tap()
        let row = app.descendants(matching: .any).matching(identifier: "profileSettings").firstMatch
        guard row.waitForExistence(timeout: 8) else { return false }
        row.tap(); return true
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
            // Navigation v1.2 rev 1.1: the dock is the cradle; there are exactly three tabs and no Profile tab
            if i == 0 {
                let dock = app.descendants(matching: .any).matching(identifier: "cradleDock").firstMatch
                XCTAssertTrue(dock.waitForExistence(timeout: 8), "the cradle dock is shown")
                for name in ["Home", "Plan", "Progress"] { XCTAssertTrue(dock.buttons[name].exists, "tab \(name) in the dock") }
                XCTAssertFalse(dock.buttons["Profile"].exists, "Profile must not be a tab")
                let ball = app.buttons["centreButton"].firstMatch, home = dock.buttons["Home"].firstMatch
                XCTAssertTrue(ball.exists && ball.frame.maxX <= home.frame.minX + 1, "the Train ball is left of Home (\(ball.frame) / \(home.frame))")
                XCTAssertEqual(ball.frame.width, 72, accuracy: 1, "Train ball is 72 pt"); XCTAssertEqual(ball.frame.height, 72, accuracy: 1)
            }
            app.settleForScreenshot(2); shot("\(tag)-1-home")
            let coach = app.buttons["homeCoachAction"].firstMatch
            if coach.exists { XCTAssertTrue(coach.label.hasPrefix("Demo, rule-based, not AI."), "\(t.id): the Coach card says it is demo and not AI (\(coach.label))") }
            if i < 2 {
                // Coach page: the Home card (or its quiet line) opens the one Coach timeline; it says rules-based, not AI
                let quiet = app.buttons["homeCoachQuiet"].firstMatch
                let card = coach.exists ? coach : quiet
                XCTAssertTrue(card.exists, "\(t.id): Home has a way into the Coach page")
                if card.exists {
                    if !card.isHittable { app.swipeUp(); app.settleForScreenshot() }
                    card.tap()
                    XCTAssertTrue(app.staticTexts["coachTitle"].firstMatch.waitForExistence(timeout: 8), "\(t.id): the Coach page opens")
                    XCTAssertTrue(app.staticTexts["coachRulesNote"].firstMatch.exists, "\(t.id): the Coach page says it follows rules and is not an AI chat")
                    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "coachComposerDisabled").firstMatch.exists, "\(t.id): asking a question is shown as not available")
                    app.settleForScreenshot(2); shot("\(tag)-1b-coach")
                    app.buttons["coachClose"].firstMatch.tap(); app.settleForScreenshot(2)
                    XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 10), "\(t.id): closing the Coach page returns to Home")
                }
            }
            app.swipeUp(); app.settleForScreenshot(); shot("\(tag)-2-home-lower")
            let centre = app.buttons["centreButton"].firstMatch
            if centre.waitForExistence(timeout: 5) { centre.tap(); app.settleForScreenshot(2); shot("\(tag)-3-train"); XCTAssertTrue(banner(app), "\(t.id): banner on Train") }
            tab(app, "Plan"); shot("\(tag)-4-plan")
            if i == 0 {
                // Plan v2.0: the schedule-first screen, fed from the athlete record (Lab: the demo athlete, and it says so)
                XCTAssertTrue(app.staticTexts["planTitle"].firstMatch.waitForExistence(timeout: 8), "Plan v2.0 is shown")
                let note = app.staticTexts["planSampleNote"].firstMatch
                XCTAssertTrue(note.exists && note.label.contains("demo athlete"), "Plan says the data is the demo athlete's")
                XCTAssertTrue(app.staticTexts["planDayHeader"].firstMatch.exists, "today's day is selected")
                app.swipeUp(); app.settleForScreenshot(); shot("\(tag)-4b-plan-lower")
            }
            tab(app, "Progress"); shot("\(tag)-5-progress")
            if i == 0 {
                // Progress: the approved compact hero, in its honest "no stage yet" state, over the real analysis
                let track = app.descendants(matching: .any).matching(identifier: "evolutionTrack").firstMatch
                XCTAssertTrue(track.waitForExistence(timeout: 8), "Progress shows the Evolution Track")
                XCTAssertFalse(app.staticTexts["heroGeneration"].firstMatch.exists, "no stage may be shown: there is no approved stage evaluation")
                XCTAssertTrue(track.label.contains("No generation yet"), "the track says no stage is evaluated (\(track.label))")
                app.swipeUp(); app.settleForScreenshot(); shot("\(tag)-5b-progress-lower")
            }
            XCTAssertTrue(openProfile(app), "\(t.id): Profile opens from the Home avatar"); shot("\(tag)-6-profile"); XCTAssertTrue(banner(app), "\(t.id): banner on Profile")
            app.terminate()
        }
    }

    /// Choosing a theme in Profile › App Preferences › Appearance changes the app at once: no relaunch, the strip names
    /// the new theme, and the picture really changes. All six, then back to the first.
    func test2ThemesSwitchWithoutRelaunch() {
        let app = XCUIApplication()
        app.launchEnvironment["LAB_THEME"] = "obsidian"
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30))
        var last = XCUIScreen.main.screenshot().pngRepresentation
        for i in Array(1..<themes.count) + [0] {
            let t = themes[i]
            XCTAssertTrue(openProfile(app), "\(t.id): Profile from the avatar")
            let prefs = app.descendants(matching: .any).matching(identifier: "profileSectionE").firstMatch
            XCTAssertTrue(prefs.waitForExistence(timeout: 8), "App Preferences"); prefs.tap()
            let appearance = app.descendants(matching: .any).matching(identifier: "profileAppearance").firstMatch
            XCTAssertTrue(appearance.waitForExistence(timeout: 8), "Appearance"); appearance.tap()
            let row = app.buttons["theme-\(t.id)"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 8), "theme row \(t.title)")
            _ = row.waitUntilHittable(timeout: 4); row.tap()
            app.settleForScreenshot(2)
            XCTAssertEqual(app.state, .runningForeground, "\(t.id): still the same running app")
            XCTAssertTrue(themeName(app).contains(t.title), "\(t.id): the strip names the theme now shown (\(themeName(app)))")
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
        XCTAssertTrue(openProfile(app), "Profile opens from the Home avatar")
        for id in ["profileSectionA", "profileSectionB", "profileSectionC", "profileSectionD", "profileSectionE", "profileSectionF"] {
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: id).firstMatch.exists, "Profile v2.0 section \(id)")
        }
        XCTAssertTrue(openSettings(app), "Profile › Data, Help & About › settings")
        var tries = 0
        let delete = app.buttons["deleteAllData"].firstMatch
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
        let restore = app.buttons["labRestore"].firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 8), "the restore button in the Lab strip"); restore.tap()
        app.settleForScreenshot(1)
        XCTAssertTrue(app.buttons["labRestore"].firstMatch.label.hasPrefix("Restore asked for"), "the strip confirms that restore was asked for")
        XCTAssertTrue(app.buttons["onboardingContinue"].firstMatch.exists, "nothing changes until Lab is reopened")
        shot("restore-1-asked")
        app.terminate()
        let again = XCUIApplication()
        again.launch()
        XCTAssertTrue(again.waitForHome(name: "Demo", timeout: 30), "after reopening, the demo athlete is back")
        shot("restore-2-back")
    }
}
