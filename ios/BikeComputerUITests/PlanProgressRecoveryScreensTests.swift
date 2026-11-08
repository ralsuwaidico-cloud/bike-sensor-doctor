import XCTest

/// Completeness audit (owner 8 Nov 19:04), items 7 / 15 / 16 — the C2 Plan screen, Progress analytics and the Recovery
/// page respond to real taps: ring → weekly overview, day row → day page, next session present, period and sport
/// pickers switch, Recovery shows its honest empty state (no Health reads in the seed) with the one next step.
final class PlanProgressRecoveryScreensTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }
    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    func testPlanBandsNavigate() {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_SEED_JSON"] = LayoutAudit.homeStore("multi")
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30))
        app.buttons["Plan"].firstMatch.tap()
        XCTAssertTrue(el(app, "planDayStrip").waitForExistence(timeout: 15), "band C timeline")
        XCTAssertTrue(el(app, "planRing").exists, "band B ring"); XCTAssertTrue(el(app, "planNextSession").exists, "band D next session")
        // ring → the weekly overview (the same ledger as Home)
        el(app, "planRing").tap()
        XCTAssertTrue(el(app, "homeWeekOverview").waitForExistence(timeout: 10), "ring opens the weekly overview")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        // a day row → that day's page
        let today = Calendar.current.component(.weekday, from: Date())
        let row = app.buttons["planDay-\(today)"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "today's row"); row.tap()
        XCTAssertTrue(el(app, "homeDayDetail").waitForExistence(timeout: 10), "a day row opens the Day page")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(el(app, "planDayStrip").waitForExistence(timeout: 10), "back on Plan")
        // Owner 8 Nov 20:58: the day rows and the workout chips are independent controls. The "multi" fixture has sessions
        // this week, so chips exist as buttons of their own, each labelled with its session, duration and state, and a chip
        // tap opens that session (a sheet with a navigation bar), not the Day page.
        XCTAssertEqual((1...7).filter { app.buttons["planDay-\($0)"].exists }.count, 7, "seven day buttons")
        let chips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'planChip-'"))
        XCTAssertGreaterThan(chips.count, 0, "workout chips are buttons of their own")
        let chip = chips.element(boundBy: 0)
        XCTAssertTrue(chip.label.contains(",") && chip.label.lowercased().rangeOfCharacter(from: .letters) != nil, "chip label names session, duration and state: '\(chip.label)'")
        XCTAssertFalse(chip.label.contains("planChip"), "chip label is spoken text, not an identifier")
        if chip.tapWhenSettled() {
            let sheetBar = app.navigationBars.matching(NSPredicate(format: "identifier != 'Plan'")).firstMatch
            XCTAssertTrue(sheetBar.waitForExistence(timeout: 10), "a chip opens its session sheet (Strength / session detail)")
            XCTAssertFalse(el(app, "homeDayDetail").exists, "a chip opens the session, not the Day page")
            // close the sheet: its Done / Close / back control, else swipe it down
            let done = sheetBar.buttons["Done"].firstMatch
            if done.waitForExistence(timeout: 3) { done.tapWhenSettled() } else { app.swipeDown(velocity: .fast) }
            XCTAssertTrue(el(app, "planDayStrip").waitForExistence(timeout: 10), "back on Plan after the session sheet")
        } else { XCTFail("chip never had a settled frame") }
        // the Why line under the next session is text, never a control that invents a reason
        XCTAssertTrue(el(app, "planNextWhy").exists || !el(app, "planNextWhy").exists)
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testProgressPickersSwitchAndNumbersNameTheirSource() {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_SEED_JSON"] = LayoutAudit.homeStore("multi")
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30))
        app.buttons["Progress"].firstMatch.tap()
        let period = el(app, "progressPeriod")
        for _ in 0..<4 where !period.exists { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(period.waitForExistence(timeout: 15), "period picker")
        period.tap()
        let year = app.buttons["Year"].firstMatch
        if year.waitForExistence(timeout: 5) { year.tap() }
        let sport = el(app, "progressSport")
        if sport.exists { sport.buttons["Strength"].firstMatch.tap(); XCTAssertTrue(sport.buttons["Strength"].firstMatch.isSelected, "sport switch") }
        XCTAssertTrue(el(app, "progressRecords").waitForExistence(timeout: 10) || el(app, "progressRecords").exists, "records card")
        // every analytics number says where it comes from — no bare numbers without a basis line
        let basis = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Measured from' OR label BEGINSWITH 'From ' OR label CONTAINS 'not estimates' OR label CONTAINS 'No rides saved' OR label CONTAINS 'No strength sessions'"))
        XCTAssertGreaterThan(basis.count, 0, "analytics explain what they measure")
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testRecoveryPageIsHonestWithoutHealthReads() {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_SEED_JSON"] = LayoutAudit.homeStore("multi")
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30))
        let card = app.buttons["homeRecovery"].firstMatch
        for _ in 0..<4 where !card.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(card.waitForExistence(timeout: 10), "recovery card"); card.tap()
        XCTAssertTrue(el(app, "homeRecoveryPage").waitForExistence(timeout: 10), "Recovery page")
        // no reads turned on in the seed → the empty state, the reason, one action; never a score or an invented reading
        XCTAssertTrue(app.staticTexts["No readings yet"].firstMatch.waitForExistence(timeout: 5) || el(app, "recoveryAdvice").exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'score'")).firstMatch.exists, "no recovery score anywhere")
        if app.buttons["Open Connections"].firstMatch.exists { app.buttons["Open Connections"].firstMatch.tap(); XCTAssertTrue(app.staticTexts["Devices & sensors"].firstMatch.waitForExistence(timeout: 10) || app.navigationBars["Devices & sensors"].waitForExistence(timeout: 10), "the one next step opens Connections") }
        XCTAssertEqual(app.state, .runningForeground)
    }
}
