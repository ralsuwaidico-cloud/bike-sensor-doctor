import XCTest

/// Cyclift Lab — FAST focused screen checks (ios/ci/lab-fast.sh). Each check launches once, in one theme, from a ready
/// demo athlete, and goes straight to the screens it is about. Required controls still fail the check when absent.
/// These are for routine screen work; the full journeys stay in LabChecks and run in the full Lab run.
final class LabFast: XCTestCase {
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
    private func tab(_ app: XCUIApplication, _ name: String) {
        let b = app.buttons[name].firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: 8), "required: tab \(name)")
        if b.exists { b.tap(); app.settleForScreenshot(1) }
    }
    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    /// Home, Plan, Progress and the Coach page, one theme, one launch.
    func testScreens() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["CYCLIFT LAB · DEMO DATA"].firstMatch.waitForExistence(timeout: 10), "required: the demo banner")
        shot("1-home")
        tab(app, "Plan")
        XCTAssertTrue(app.staticTexts["planTitle"].firstMatch.waitForExistence(timeout: 8), "required: Plan is shown")
        XCTAssertTrue(app.staticTexts["planDayHeader"].firstMatch.exists, "required: today's day is selected")
        shot("2-plan")
        let row = el(app, "planCoachRow")
        if row.exists {
            row.tap()
            XCTAssertTrue(el(app, "coachTimeline").waitForExistence(timeout: 8), "required: the Plan row opens the Coach page")
            shot("3-coach")
            app.buttons["coachClose"].firstMatch.tap(); app.settleForScreenshot(1)
        }
        tab(app, "Progress")
        XCTAssertTrue(el(app, "evolutionTrack").waitForExistence(timeout: 8), "required: Progress shows the Evolution Track")
        shot("4-progress")
    }

    /// Plan with an open Coach suggestion (fixture LAB_DEMO_PROPOSAL): the row and the Coach page with Not now · Review.
    func testOpenSuggestion() {
        let app = launch(["LAB_DEMO_PROPOSAL": "1"])
        tab(app, "Plan")
        let row = el(app, "planCoachRow")
        XCTAssertTrue(row.waitForExistence(timeout: 8), "required: Plan shows the Coach row")
        XCTAssertTrue(row.label.hasPrefix("Coach Suggests") && row.label.hasSuffix("Review"), "required: an open suggestion offers Review (\(row.label))")
        shot("5-plan-open-suggestion")
        row.tap()
        XCTAssertTrue(el(app, "coachTimeline").waitForExistence(timeout: 8), "required: the Coach page opens")
        let notNow = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'coachNotNow-'")).firstMatch
        XCTAssertTrue(notNow.waitForExistence(timeout: 8), "required: Not now is offered")
        _ = app.reveal(notNow)
        shot("6-coach-open-suggestion")
    }

    /// Profile sheet P03: Athlete Profile, Personal details (edit the name, Save lights, the name is stored) and
    /// Type & experience (the four controls; Save stays unlit until something changes).
    func testProfileAthletePages() {
        let app = launch()
        let avatar = app.buttons["homeAvatar"].firstMatch
        XCTAssertTrue(avatar.waitForExistence(timeout: 8), "required: the Home avatar"); avatar.tap(); app.settleForScreenshot(1)
        let a = el(app, "profileSectionA")
        XCTAssertTrue(a.waitForExistence(timeout: 8), "required: Profile landing"); a.tap(); app.settleForScreenshot(1)
        shot("p03-A-athlete-profile")
        let personal = el(app, "profilePersonal")
        XCTAssertTrue(personal.waitForExistence(timeout: 8), "required: Personal details row"); personal.tap(); app.settleForScreenshot(1)
        let name = app.textFields["personalName"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 8), "required: the name field")
        XCTAssertTrue(el(app, "personalDOB").exists, "required: date of birth"); XCTAssertTrue(app.textFields["personalWeight"].firstMatch.exists, "required: weight")
        let save = app.buttons["personalSave"].firstMatch
        XCTAssertTrue(save.exists, "required: Save in the bar"); XCTAssertFalse(save.isEnabled, "Save is unlit until something changes")
        shot("p03-A1-personal-details")
        name.tap(); name.typeText(" Lab")
        XCTAssertTrue(save.isEnabled, "required: Save lights after a change")
        shot("p03-A1-personal-details-changed")
        save.tap(); app.settleForScreenshot(1)
        XCTAssertTrue(personal.waitForExistence(timeout: 8), "required: back on Athlete Profile after Save")
        XCTAssertTrue(personal.label.contains("Demo Lab"), "required: the saved name is shown (\(personal.label))")
        let type = el(app, "profileType")
        XCTAssertTrue(type.waitForExistence(timeout: 8), "required: Athlete type row"); type.tap(); app.settleForScreenshot(1)
        for id in ["typeMode", "typeBalance", "typeRiding", "typeLifting"] { XCTAssertTrue(el(app, id).waitForExistence(timeout: 8), "required: \(id)") }
        XCTAssertFalse(app.buttons["typeSave"].firstMatch.isEnabled, "Save is unlit until something changes")
        shot("p03-A3-type-experience")
    }
}
